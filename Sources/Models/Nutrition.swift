import Foundation

/// Provenance of a logged entry:
///   • `manual`: hand-typed
///   • `aiEstimated`: AI macro estimate (raw value "ai-estimated")
///   • `saved`: re-logged from a saved meal / recent (already-confirmed macros)
enum FoodSource: String, Codable, Equatable, CaseIterable, Sendable {
    case manual
    case aiEstimated = "ai-estimated"
    case saved
}

/// A single logged food entry.
struct FoodEntry: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var source: FoodSource
    /// ISO 8601 timestamp of when this entry was logged.
    var loggedAt: String
}

/// Daily goal targets (calories, macros, steps). `stepsGoal` is the target the user sets; the
/// actual step count still comes from Whoop.
///
/// Goals persisted before `stepsGoal` existed still decode. See `init(from:)`.
struct Goals: Codable, Equatable, Sendable {
    var calorieGoal: Double
    var proteinGoal: Double
    var fatGoal: Double
    var carbGoal: Double
    /// Daily step target. Default 10,000. An editable starting point, never a recommendation.
    var stepsGoal: Int

    /// Default targets: an editable starting point, not a recommendation.
    /// ~2200 kcal / 160 g protein / 73 g fat / 206 g carb / 10,000 steps.
    static let `default` = Goals(
        calorieGoal: 2200, proteinGoal: 160, fatGoal: 73, carbGoal: 206, stepsGoal: 10_000
    )

    init(calorieGoal: Double, proteinGoal: Double, fatGoal: Double, carbGoal: Double, stepsGoal: Int) {
        self.calorieGoal = calorieGoal
        self.proteinGoal = proteinGoal
        self.fatGoal = fatGoal
        self.carbGoal = carbGoal
        self.stepsGoal = stepsGoal
    }

    /// Backward-compatible decode: `stepsGoal` may be absent in older data, so it defaults to
    /// 10,000 instead of throwing.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        calorieGoal = try c.decode(Double.self, forKey: .calorieGoal)
        proteinGoal = try c.decode(Double.self, forKey: .proteinGoal)
        fatGoal = try c.decode(Double.self, forKey: .fatGoal)
        carbGoal = try c.decode(Double.self, forKey: .carbGoal)
        stepsGoal = try c.decodeIfPresent(Int.self, forKey: .stepsGoal) ?? 10_000
    }
}

/// The goals that became active on `effectiveFrom` (local YYYY-MM-DD). The legacy seed uses "" so
/// it sorts before every real day. Each day is judged against the version active that day, so
/// recalculating a goal never rewrites streak history.
struct GoalsVersion: Codable, Equatable, Sendable {
    var effectiveFrom: String
    var goals: Goals
}

/// Saved goal-calculator inputs (activity level + pace), as raw enum values. With auto-adjust on,
/// the calorie/macro goals re-derive from the current weight through this recipe whenever the
/// weight changes.
struct GoalRecipe: Codable, Equatable, Sendable {
    var activity: String
    var direction: String
}

/// A saved, reusable meal template. Re-logging one creates a `FoodEntry` with already-confirmed
/// macros (source `.saved`).
struct SavedMeal: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    /// ISO 8601: when the template was first saved.
    var createdAt: String
    /// ISO 8601: when it was last re-logged.
    var lastUsedAt: String
    /// How many times it's been re-logged. Sorts the "Saved & recent" list.
    var useCount: Int
}

/// A previously-logged meal surfaced for one-tap re-logging. Shares SavedMeal's macro shape so the
/// UI can treat both uniformly, plus use count / recency for ordering.
struct RecentMeal: Codable, Equatable, Sendable {
    var name: String
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var useCount: Int
    var lastUsedAt: String
}

/// Summed calories/protein/carbs/fat for one day.
struct DailyTotals: Codable, Equatable, Sendable {
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double

    /// The all-zero totals.
    static let zero = DailyTotals(calories: 0, proteinG: 0, carbsG: 0, fatG: 0)
}
