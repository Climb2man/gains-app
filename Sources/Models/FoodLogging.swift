import Foundation

/// Goal-driven calorie bias: seven levels whose raw values `underestimate_high` … `overestimate_high`
/// are the stored strings. The conservative bias protects the user's goal: cutting → overestimate
/// (logged ≥ actual protects the deficit), bulking → underestimate. Chosen in onboarding, overridable
/// in Settings, and disclosed in the UI: a safety nudge, not exact truth.
///
/// `bufferPercent` is the signed % the prompt applies. `overestimate_high = +20%`; the low/medium
/// levels are graduated around it.
enum CalorieBias: String, Codable, Equatable, CaseIterable, Sendable {
    case underestimateHigh = "underestimate_high"
    case underestimateMedium = "underestimate_medium"
    case underestimateLow = "underestimate_low"
    case balanced = "balanced"
    case overestimateLow = "overestimate_low"
    case overestimateMedium = "overestimate_medium"
    case overestimateHigh = "overestimate_high"

    /// Signed buffer the prompt applies to calories + macros. `overestimate_high = +20%`; the rest are
    /// graduated around it.
    var bufferPercent: Int {
        switch self {
        case .underestimateHigh: -20
        case .underestimateMedium: -10
        case .underestimateLow: -5
        case .balanced: 0
        case .overestimateLow: 5
        case .overestimateMedium: 10
        case .overestimateHigh: 20
        }
    }

    /// The picker title (the labels at the extremes: "Overestimate More" / "Underestimate More").
    var title: String {
        switch self {
        case .underestimateHigh: "Underestimate More"
        case .underestimateMedium: "Underestimate"
        case .underestimateLow: "Underestimate Slightly"
        case .balanced: "Balanced"
        case .overestimateLow: "Overestimate Slightly"
        case .overestimateMedium: "Overestimate"
        case .overestimateHigh: "Overestimate More"
        }
    }

    /// The picker description (graduated for the in-between levels).
    var pickerDescription: String {
        switch self {
        case .underestimateHigh:
            "Aggressively reduce estimates beyond the lower range. Best for those in a gaining phase who want to avoid undereating."
        case .underestimateMedium: "Lean low. Best for gaining phases, to avoid undereating."
        case .underestimateLow: "Trim estimates slightly below the best guess."
        case .balanced: "Use the most accurate data available without adjustment. Balanced approach for precise tracking."
        case .overestimateLow: "Pad estimates slightly above the best guess."
        case .overestimateMedium: "Lean high. Best for cutting phases, with a safety margin."
        case .overestimateHigh:
            "Aggressively increase estimates beyond the upper range. Best for those in a cutting phase who want extra safety margin."
        }
    }

    /// The default bias for a goal type: `lose` → overestimate, `gain` → underestimate, else balanced,
    /// at the moderate level. The user can dial it up or down in the onboarding picker.
    static func `default`(for goalType: String) -> CalorieBias {
        switch goalType.lowercased() {
        case "lose": .overestimateMedium
        case "gain": .underestimateMedium
        default: .balanced
        }
    }

    /// The one-line disclosure shown under estimates so the lean is never hidden.
    var disclosure: String {
        switch direction {
        case .over: "Estimates lean high to protect your deficit."
        case .under: "Estimates lean low to protect your surplus."
        case .none: "Estimates are a balanced best guess."
        }
    }

    /// A short label for the bias chip on an estimated row.
    var shortLabel: String {
        switch direction {
        case .over: "Leans high"
        case .under: "Leans low"
        case .none: "Balanced"
        }
    }

    /// Which way the lean goes: drives the disclosure/chip copy so they need no per-level switch.
    enum Direction { case under, none, over }
    var direction: Direction {
        if bufferPercent > 0 { .over } else if bufferPercent < 0 { .under } else { .none }
    }

    /// Decode tolerantly: legacy "overestimate"/"underestimate" map onto the aggressive levels, and any
    /// unknown string falls back to balanced rather than failing and resetting the user's setting.
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "overestimate": self = .overestimateHigh
        case "underestimate": self = .underestimateHigh
        default: self = CalorieBias(rawValue: raw) ?? .balanced
        }
    }
}

/// Which optional micronutrients the user tracks. When on, the totals bar adds sugar / fiber / sodium
/// rows and the pipeline returns them. Off by default; calories + P/C/F are the headline.
struct MicronutrientToggles: Codable, Equatable, Sendable {
    var sugar: Bool
    var fiber: Bool
    var sodium: Bool

    static let off = MicronutrientToggles(sugar: false, fiber: false, sodium: false)

    /// True when any micronutrient is tracked. Drives whether the totals bar shows the extra row.
    var anyEnabled: Bool { sugar || fiber || sodium }
}

/// Where an item's numbers came from: drives the row's first chip. `.stated` = the user typed the
/// values (we did the math in code); `.estimate` = the AI/database estimated them. Optional, treated
/// as `.estimate` when nil, so historical entries with no provenance key decode unchanged.
enum FoodProvenance: String, Codable, Sendable {
    case stated
    case estimate
    /// Reused from a previously-resolved entry in the on-device cache. No new lookup/AI call. Shown so
    /// the user knows the number is a saved one, not a fresh estimate.
    case cached
}

/// One resolved item within a logged line; the pipeline may split a natural-language line into several.
/// Macros are estimates: `confidenceScore`, `assumptions`, and `citations` keep that honest.
struct LoggedFoodItem: Codable, Equatable, Identifiable, Sendable {
    var id: String
    /// The resolved item name (e.g. "Greco Pork Gyro (Pita + Pork + Veg)").
    var name: String
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    /// Optional micronutrients (grams for sugar/fiber, milligrams for sodium), nil when not resolved.
    var sugarG: Double?
    var fiberG: Double?
    var sodiumMg: Double?
    /// Real source URLs the estimate used. Empty for cache/saved/offline items.
    var citations: [String]
    /// Short reasoning/assumptions string, shown on tap for transparency.
    var assumptions: String?
    /// 0…100 confidence: drives the confidence chip on the row.
    var confidenceScore: Int?
    /// Water phrasing → excluded from calorie totals. When true, `calories` must be 0.
    var isWaterEntry: Bool
    /// Volume for a water entry, in milliliters (stored metric; UX shows imperial). Nil for food.
    var waterMilliliters: Double?
    /// Where the numbers came from. Optional so old persisted entries (no key) decode as nil; the UI
    /// treats nil as `.estimate`. Only the stated-nutrition lane sets `.stated`.
    var provenance: FoodProvenance?

    init(
        id: String = UUID().uuidString,
        name: String,
        calories: Double,
        proteinG: Double = 0,
        carbsG: Double = 0,
        fatG: Double = 0,
        sugarG: Double? = nil,
        fiberG: Double? = nil,
        sodiumMg: Double? = nil,
        citations: [String] = [],
        assumptions: String? = nil,
        confidenceScore: Int? = nil,
        isWaterEntry: Bool = false,
        waterMilliliters: Double? = nil,
        provenance: FoodProvenance? = nil
    ) {
        self.id = id
        self.name = name
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.sugarG = sugarG
        self.fiberG = fiberG
        self.sodiumMg = sodiumMg
        self.citations = citations
        self.assumptions = assumptions
        self.confidenceScore = confidenceScore
        self.isWaterEntry = isWaterEntry
        self.waterMilliliters = waterMilliliters
        self.provenance = provenance
    }

    /// A copy scaled by `factor`, the portion multiplier for "re-log ½× / 2×" quick-add. Calories,
    /// macros, micronutrients, and water volume scale; name, citations, assumptions, and provenance
    /// carry over unchanged. A factor of 1 returns the item untouched.
    func scaled(by factor: Double) -> LoggedFoodItem {
        guard factor != 1, factor > 0 else { return self }
        var copy = self
        copy.calories = calories * factor
        copy.proteinG = proteinG * factor
        copy.carbsG = carbsG * factor
        copy.fatG = fatG * factor
        copy.sugarG = sugarG.map { $0 * factor }
        copy.fiberG = fiberG.map { $0 * factor }
        copy.sodiumMg = sodiumMg.map { $0 * factor }
        copy.waterMilliliters = waterMilliliters.map { $0 * factor }
        return copy
    }
}

/// How a logged line is currently resolving. Drives the optimistic line + loading state:
/// the row appears instantly as `.pending`, then flips to `.resolved` when macros fill in, or
/// `.failed` if the pipeline couldn't estimate (the user can edit/retype by hand).
enum FoodEntryStatus: String, Codable, Equatable, Sendable {
    case pending
    case resolved
    case failed
}

/// One Apple-Notes-style line in the day's log. Stores the user's raw typed text plus the resolved
/// item(s) the pipeline produced. Line calories = sum of item calories (water excluded). Stores a real
/// `loggedAt` timestamp, not just a date.
struct FoodJournalEntry: Codable, Equatable, Identifiable, Sendable {
    var id: String
    /// The user's original natural-language text for this line (what they typed / re-typed).
    var foodText: String
    /// The resolved items (one line may split into several). Empty while `.pending`.
    var items: [LoggedFoodItem]
    /// Resolution state for the optimistic UI.
    var status: FoodEntryStatus
    /// ISO 8601 timestamp (with fractional seconds) of when the line was logged.
    var loggedAt: String

    init(
        id: String = UUID().uuidString,
        foodText: String,
        items: [LoggedFoodItem] = [],
        status: FoodEntryStatus = .pending,
        loggedAt: String
    ) {
        self.id = id
        self.foodText = foodText
        self.items = items
        self.status = status
        self.loggedAt = loggedAt
    }

    /// Calories for the line = sum of item calories. Water items contribute 0 (water is
    /// excluded from calories), enforced here so the totals bar can't double-count.
    var totalCalories: Double {
        items.reduce(0) { $0 + ($1.isWaterEntry ? 0 : $1.calories) }
    }

    /// True when every resolved item is a water entry (a pure-water line), shown with a drop glyph and
    /// no calorie value. An empty/pending line is not water.
    var isWaterOnly: Bool {
        !items.isEmpty && items.allSatisfy(\.isWaterEntry)
    }

    /// The display title for the row: the user's text, falling back to the first item's name if the
    /// pipeline produced a cleaner name and the user typed nothing meaningful.
    var displayTitle: String {
        let trimmed = foodText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return items.first?.name ?? "Food"
    }
}

/// The bottom totals bar's summed values for one day: calories + P/C/F always, plus
/// sugar/fiber/sodium when those toggles are on. Pure data the view formats against the user's goals.
struct FoodDayTotals: Equatable, Sendable {
    var calories: Double = 0
    var proteinG: Double = 0
    var carbsG: Double = 0
    var fatG: Double = 0
    var sugarG: Double = 0
    var fiberG: Double = 0
    var sodiumMg: Double = 0
    /// Total water logged for the day, in milliliters (shown separately, never as calories).
    var waterMilliliters: Double = 0

    static let zero = FoodDayTotals()
}

/// A nicknamed, re-loggable food/meal. Stores the full resolved snapshot (items + macros + citations)
/// so recalling it inserts instantly with no AI calls, offline. `useCount` orders the quick-add
/// suggestions (most-used first).
struct FoodShortcut: Codable, Equatable, Identifiable, Sendable {
    var id: String
    /// The user's nickname, e.g. "regular Chipotle order". Autocompletes as they type.
    var nickname: String
    /// The full resolved snapshot to re-insert (items carry their macros + citations).
    var items: [LoggedFoodItem]
    /// Where this shortcut came from (e.g. "log" for inline-saved). Free-form.
    var source: String
    /// How many times it's been re-logged. Sorts the quick-add row.
    var useCount: Int
    /// User-pinned to the top of the Saved Meals list, above the use-count ordering. Optional so old
    /// persisted shortcuts (no key) decode as nil; nil + false both mean "not pinned".
    var isPinned: Bool?
    /// ISO 8601 timestamps.
    var createdAt: String
    var updatedAt: String

    init(
        id: String = UUID().uuidString,
        nickname: String,
        items: [LoggedFoodItem],
        source: String = "log",
        useCount: Int = 0,
        isPinned: Bool? = nil,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.nickname = nickname
        self.items = items
        self.source = source
        self.useCount = useCount
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Whether this meal is pinned (nil → false).
    var pinned: Bool { isPinned == true }

    /// Summed calories for the chip subtitle (water excluded, mirroring `FoodJournalEntry`).
    var totalCalories: Double {
        items.reduce(0) { $0 + ($1.isWaterEntry ? 0 : $1.calories) }
    }
}

/// What the UX hands the pipeline to resolve a new line: the raw text, the active bias, and which
/// micronutrients to ask for. The pipeline routes saved/cache/bundled-DB/cheap/novel internally.
struct FoodLineRequest: Sendable {
    var text: String
    var bias: CalorieBias
    var micronutrients: MicronutrientToggles

    init(text: String, bias: CalorieBias = .balanced, micronutrients: MicronutrientToggles = .off) {
        self.text = text
        self.bias = bias
        self.micronutrients = micronutrients
    }
}

/// What the UX hands the pipeline to edit an existing line: the old + new text plus the already-
/// resolved items, so the pipeline can take the cheap portion-only path ("burrito" → "half a burrito")
/// and skip web search entirely.
struct FoodEditRequest: Sendable {
    var oldText: String
    var newText: String
    var existingItems: [LoggedFoodItem]
    var bias: CalorieBias
    var micronutrients: MicronutrientToggles

    init(
        oldText: String,
        newText: String,
        existingItems: [LoggedFoodItem],
        bias: CalorieBias = .balanced,
        micronutrients: MicronutrientToggles = .off
    ) {
        self.oldText = oldText
        self.newText = newText
        self.existingItems = existingItems
        self.bias = bias
        self.micronutrients = micronutrients
    }
}

/// The pipeline's result for one line: the resolved item(s) the UX writes onto the optimistic entry.
/// A struct, not a bare array, so the pipeline can grow per-line metadata without breaking callers.
struct FoodLineResult: Sendable {
    var items: [LoggedFoodItem]

    init(items: [LoggedFoodItem]) {
        self.items = items
    }
}
