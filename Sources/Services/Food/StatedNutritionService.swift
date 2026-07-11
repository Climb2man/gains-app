import Foundation

enum StatedNutrition {
    /// True iff the line states an explicit nutrition value: a calorie figure or a macro in grams. A
    /// bare quantity/serving phrase ("1.5 lb of chicken", "2x rice", "chipotle bowl") is not a nutrition
    /// value, so it returns false and keeps the normal OFF/Sonar/brand path. Cheap gate so a non-stated
    /// line adds no AI latency; the extractor runs only on a hit.
    static func mightStateNutrition(_ text: String) -> Bool {
        let s = text.lowercased()
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        return patterns.contains { $0.firstMatch(in: s, range: range) != nil }
    }

    /// Compiled once. (a) a calorie statement; (b) a macro-with-grams statement in either word order.
    nonisolated(unsafe) private static let patterns: [NSRegularExpression] = [
        #"\b\d+(\.\d+)?\s?(k?cals?|calories|kcal)\b"#,
        #"\b\d+(\.\d+)?\s?g\s?(protein|carbs?|carbohydrates?|fat|fats)\b"#,
        #"\b(protein|carbs?|carbohydrates?|fat|fats)\s*:?\s*\d+(\.\d+)?\s?g\b"#,
    ].compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
}

/// The strict JSON the model returns for a stated line. The model copies the user's numbers verbatim
/// and does no arithmetic; all optionals decode tolerantly (a partial object never throws).
struct StatedNutritionWire: Codable, Sendable {
    var statesNutrition: Bool
    var name: String?
    var basis: Basis?
    var per: PerBlock?
    var serving: Measure?
    var total: Measure?
    var servingsCount: Double?

    enum Basis: String, Codable, Sendable { case perServing = "per_serving", total }

    struct PerBlock: Codable, Sendable {
        var calories: Double?
        var protein_g: Double?
        var carbs_g: Double?
        var fat_g: Double?
        var sugar_g: Double?
        var fiber_g: Double?
        var sodium_mg: Double?
    }

    struct Measure: Codable, Sendable {
        var amount: Double?
        var unit: Unit?
    }

    enum Unit: String, Codable, Sendable { case g, oz, lb, ml }
}

enum StatedNutritionMath {
    static let gramsPerOz = 28.349523125
    static let gramsPerLb = 453.59237

    /// Grams for a measure; ml treated as g (we only need a ratio, the units cancel). nil if unusable.
    static func grams(_ m: StatedNutritionWire.Measure?) -> Double? {
        guard let m, let amt = m.amount, let unit = m.unit, amt > 0 else { return nil }
        switch unit {
        case .g, .ml: return amt
        case .oz: return amt * gramsPerOz
        case .lb: return amt * gramsPerLb
        }
    }

    /// Multiplier from a per-serving block to the total eaten. A mass serving/total pair wins; else a
    /// bare servingsCount ("per serving, 3 servings"); else 1.0.
    static func scale(
        serving: StatedNutritionWire.Measure?,
        total: StatedNutritionWire.Measure?,
        servingsCount: Double?
    ) -> Double {
        if let sg = grams(serving), let tg = grams(total), sg > 0 { return tg / sg }
        if let n = servingsCount, n > 0 { return n }
        return 1.0
    }
}

/// The seam the router depends on (so it can be stubbed in tests). Returns nil when the line doesn't
/// state nutrition, and the router falls through to the normal lanes.
protocol StatedNutritionResolver: Sendable {
    func resolve(line: String, micronutrients: MicronutrientToggles) async throws -> [LoggedFoodItem]?
}

/// `StatedNutritionResolver` over the food AI's extract-only call. Pure extract plus Swift math; never
/// touches the bias, the reconcile pass, or the database lanes.
struct StatedNutritionService: StatedNutritionResolver {
    private let ai: any FoodNutritionAI

    init(ai: any FoodNutritionAI) {
        self.ai = ai
    }

    func resolve(line: String, micronutrients: MicronutrientToggles) async throws -> [LoggedFoodItem]? {
        let wire = try await ai.extractStated(line: line)
        guard wire.statesNutrition, let per = wire.per, Self.hasAnyValue(per) else { return nil }

        let scale = (wire.basis == .perServing)
            ? StatedNutritionMath.scale(serving: wire.serving, total: wire.total, servingsCount: wire.servingsCount)
            : 1.0

        var protein = per.protein_g.map { ($0 * scale) }
        var carbs = per.carbs_g.map { ($0 * scale) }
        var fat = per.fat_g.map { ($0 * scale) }

        let calories: Double
        if let statedCal = per.calories {
            calories = (statedCal * scale).rounded()
        } else {
            calories = ((protein ?? 0) * 4 + (carbs ?? 0) * 4 + (fat ?? 0) * 9).rounded()
        }

        if per.calories != nil {
            let knownCal = (protein ?? 0) * 4 + (carbs ?? 0) * 4 + (fat ?? 0) * 9
            let gap = calories - knownCal
            if gap > 5 {
                if fat == nil && carbs == nil {
                    fat = gap / 9
                    carbs = 0
                } else if fat == nil {
                    fat = gap / 9
                } else if carbs == nil {
                    carbs = gap / 4
                }
            }
        }

        let item = LoggedFoodItem(
            name: Self.cleanName(wire.name, fallback: line),
            calories: calories,
            proteinG: round1(protein ?? 0),
            carbsG: round1(carbs ?? 0),
            fatG: round1(fat ?? 0),
            sugarG: micronutrients.sugar ? per.sugar_g.map { round1($0 * scale) } : nil,
            fiberG: micronutrients.fiber ? per.fiber_g.map { round1($0 * scale) } : nil,
            sodiumMg: micronutrients.sodium ? per.sodium_mg.map { round1($0 * scale) } : nil,
            citations: [],
            assumptions: Self.note(scale: scale, basis: wire.basis, serving: wire.serving, total: wire.total),
            confidenceScore: 100,
            provenance: .stated
        )
        return [item]
    }

    private static func hasAnyValue(_ p: StatedNutritionWire.PerBlock) -> Bool {
        p.calories != nil || p.protein_g != nil || p.carbs_g != nil || p.fat_g != nil
    }

    private func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }

    /// The honest note shown on tap: what the user stated and how it was scaled.
    private static func note(
        scale: Double, basis: StatedNutritionWire.Basis?,
        serving: StatedNutritionWire.Measure?, total: StatedNutritionWire.Measure?
    ) -> String {
        guard basis == .perServing, scale != 1.0,
              let s = serving, let sa = s.amount, let su = s.unit,
              let t = total, let ta = t.amount, let tu = t.unit
        else { return "From your numbers." }
        let mult: Double = (scale * 100).rounded() / 100
        let perPart: String = "per " + trim(sa) + " " + su.rawValue
        let toPart: String = "to " + trim(ta) + " " + tu.rawValue
        return "From your numbers: " + perPart + ", scaled ×" + trim(mult) + " " + toPart + "."
    }

    private static func trim(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }

    /// Use the AI-stripped name when it's meaningful; else the user's raw line.
    private static func cleanName(_ name: String?, fallback: String) -> String {
        let n = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { return n }
        let f = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return f.isEmpty ? "Food" : f
    }
}
