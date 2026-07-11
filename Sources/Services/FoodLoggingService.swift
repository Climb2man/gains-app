import Foundation

/// Resolves a free-text food line into one or more `LoggedFoodItem`s, applying the goal-driven bias and
/// the cheap portion path for edits. Implementations own the routing (saved → cache → bundled-DB →
/// cheap → novel); callers just await items.
protocol FoodLoggingService: Sendable {
    /// Resolve a brand-new line. Returns the resolved item(s); one line may split into several. Throws
    /// `FoodLoggingError.missingKey` when no OpenRouter key is stored (the UI routes to Settings, never
    /// retried) or `.transient` when an AI lane failed in a way a retry might fix (network/parse). The
    /// caller owns retry and the offline fallback: `FoodLogStore` runs attempts through its
    /// `BackgroundTaskQueue` and applies `FoodLoggingFallback.offlineItem` only after retries exhaust,
    /// so the user always ends with an editable number, never a silent loss.
    func resolveLine(_ request: FoodLineRequest) async throws -> FoodLineResult

    /// Resolve an edit to an existing line. A portion-only change uses the cheap path and never triggers
    /// web search; substantive new content resolves like a novel line. Same throwing contract as
    /// `resolveLine`; on exhausted retries the caller keeps the line's existing items via
    /// `FoodLoggingFallback.markFallback` (better than zeroing).
    func resolveEdit(_ request: FoodEditRequest) async throws -> FoodLineResult
}

/// The two throwing cases of the pipeline seam. `missingKey` routes to Settings and is never retried;
/// `transient` asks the caller's queue for another attempt before the offline fallback.
enum FoodLoggingError: Error, Equatable, Sendable {
    case missingKey
    case transient
}

/// Deterministic on-device fallbacks applied after retries exhaust. Live on the seam, not the router,
/// because the retry loop (`FoodLogStore` + `BackgroundTaskQueue`) decides when every AI path has
/// failed. Never a fabricated cited number: zeroed or confidence-0 only.
enum FoodLoggingFallback {
    /// A zeroed, editable placeholder for a new line that couldn't resolve; the UX shows the manual
    /// macro fields, labeled honestly.
    static func offlineItem(text: String) -> LoggedFoodItem {
        LoggedFoodItem(
            name: text, calories: 0,
            assumptions: "Estimated on-device (offline). Couldn't reach the AI service. Enter macros.",
            confidenceScore: 0
        )
    }

    /// Tag an existing item as an offline fallback (confidence 0 + honest note) without altering its
    /// numbers, for when an edit can't reach the model but the prior items are still the best data.
    static func markFallback(_ item: LoggedFoodItem) -> LoggedFoodItem {
        var copy = item
        copy.confidenceScore = 0
        let note = "Estimated on-device (offline). Couldn't reach the AI service."
        copy.assumptions = copy.assumptions.map { "\($0) \(note)" } ?? note
        return copy
    }
}

/// Detects water/volume phrasing entirely on-device so a water line is never sent for a calorie
/// estimate. Pure + Sendable so the UX can also use it to preview the water glyph.
enum WaterPhrasing {
    /// Common volume words that, combined with "water", mark a water entry. Conservative on purpose:
    /// "watermelon"/"coconut water"/"sparkling water with juice" aren't all zero-calorie, so we only
    /// match clear water phrasings and let the user correct the rest.
    static func parse(_ text: String) -> (isWater: Bool, milliliters: Double?) {
        let lowered = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let mentionsWater = lowered.localizedStandardContains("water")
        let isPlainWater = mentionsWater
            && !lowered.localizedStandardContains("watermelon")
            && !lowered.localizedStandardContains("coconut water")
            && !lowered.localizedStandardContains("sparkling water with")
        guard isPlainWater else { return (false, nil) }
        return (true, estimateMilliliters(lowered))
    }

    /// Best-effort volume parse from the phrasing (e.g. "16 oz water", "a glass of water"). Returns nil
    /// when no volume is stated; the UX still logs it as water, just without a milliliter value.
    private static func estimateMilliliters(_ lowered: String) -> Double? {
        let mlPerFlOz = 29.5735
        let glassMl = 240.0
        let bottleMl = 500.0

        let firstNumber: Double? = {
            var digits = ""
            for character in lowered {
                if character.isNumber || character == "." {
                    digits.append(character)
                } else if !digits.isEmpty {
                    break
                }
            }
            return Double(digits)
        }()

        if let value = firstNumber {
            if lowered.localizedStandardContains("oz") { return value * mlPerFlOz }
            if lowered.localizedStandardContains("ml") { return value }
            if lowered.localizedStandardContains("l ") || lowered.hasSuffix("l") {
                return value * 1000
            }
            if lowered.localizedStandardContains("glass") { return value * glassMl }
            if lowered.localizedStandardContains("bottle") { return value * bottleMl }
            if lowered.localizedStandardContains("cup") { return value * glassMl }
        }
        if lowered.localizedStandardContains("glass") { return glassMl }
        if lowered.localizedStandardContains("bottle") { return bottleMl }
        return nil
    }
}
