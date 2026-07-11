import Foundation

enum FoodLogFormat {
    private static let mlPerFlOz = 29.5735

    /// A short macro line for a row subtitle, e.g. "41P · 60C · 42F". Rounded whole grams.
    static func macroLine(protein: Double, carbs: Double, fat: Double) -> String {
        "\(Format.int(protein))P · \(Format.int(carbs))C · \(Format.int(fat))F"
    }

    /// A water volume in imperial, e.g. "16 fl oz". The word "water" is not appended because callers
    /// already say it (the row's drop glyph and title, the strip's "Water" label). Falls back to "Water"
    /// only when no volume is known.
    static func water(_ milliliters: Double?) -> String {
        guard let milliliters, milliliters > 0 else { return "Water" }
        let flOz = milliliters / mlPerFlOz
        return "\(Format.int(flOz)) fl oz"
    }

    /// A "x / goal kcal" headline for the totals bar.
    static func caloriesVsGoal(_ value: Double, goal: Double) -> String {
        "\(Format.int(value)) / \(Format.int(goal)) kcal"
    }

    /// A plain-language confidence label from a 0–100 score.
    static func confidenceLabel(_ score: Int?) -> String? {
        guard let score else { return nil }
        switch score {
        case 75...: return "High confidence"
        case 45..<75: return "Medium confidence"
        default: return "Low confidence"
        }
    }

    /// The confidence tone for the chip (success / warning / danger, neutral when there's no score),
    /// so low confidence reads cautious.
    static func confidenceTone(_ score: Int?) -> Pill.Tone {
        guard let score else { return .neutral }
        switch score {
        case 75...: return .success
        case 45..<75: return .warning
        default: return .danger
        }
    }

    /// The confidence status for a `StatusBadge` (good / warning / bad), so low confidence reads cautious.
    /// Describes the estimate's certainty, never the food or the person.
    static func confidenceStatus(_ score: Int?) -> StatusTone {
        guard let score else { return .neutral }
        switch score {
        case 75...: return .good
        case 45..<75: return .warning
        default: return .bad
        }
    }
}
