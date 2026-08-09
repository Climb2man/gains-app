import XCTest
@testable import Gains

@MainActor
final class GoalsTimelineTests: XCTestCase {

    private func isolatedStore(_ name: String) -> UserDefaultsStore {
        let suiteName = "gains.test.goals-timeline.\(name)"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        return UserDefaultsStore(defaults: suite)
    }

    /// An entry logged at noon-local `daysAgo`, with chosen calories/protein.
    private func entry(daysAgo: Int, calories: Double, protein: Double) -> FoodEntry {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: -daysAgo, to: Date())!
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
        return FoodEntry(id: UUID().uuidString, name: "meal", calories: calories,
                         proteinG: protein, carbsG: 0, fatG: 0,
                         source: .manual, loggedAt: ISO8601DateFormatter().string(from: noon))
    }

    private let baseProfile = Profile(
        name: nil, sex: .male, ageYears: 20, heightCm: 178, weightKg: 93.4,
        createdAt: "2026-06-01T00:00:00.000Z"
    )


    /// A recipe written by the previous goal model stores directions like "lose1". Those must not
    /// resolve, so the user's existing targets survive untouched until they pick a new goal.
    func testLegacyRecipeDirectionLeavesGoalsAlone() {
        let store = NutritionStore(store: isolatedStore("legacy-recipe"))
        let before = store.goals
        store.setGoalRecipe(GoalRecipe(activity: "moderate", direction: "lose1"), autoAdjust: true)
        store.autoAdjustGoals(profile: baseProfile)
        XCTAssertEqual(store.goals, before,
                       "an unresolvable legacy direction must be a strict no-op, not a reset")
    }

    func testLegacyGoalsCoverAllHistory() {
        let kv = isolatedStore("legacy")
        kv.setValue(Goals(calorieGoal: 1800, proteinGoal: 120, fatGoal: 60, carbGoal: 180, stepsGoal: 8000),
                    forKey: "@gains/nutrition/goals")
        let store = NutritionStore(store: kv)

        XCTAssertEqual(store.goals(on: "2020-01-01").calorieGoal, 1800, "the seed must cover ancient days")
        XCTAssertEqual(store.goals(on: NutritionStore.dayKey(Date())).calorieGoal, 1800)
    }

    func testGoalChangeTakesEffectTodayNotRetroactively() {
        let store = NutritionStore(store: isolatedStore("effective-today"))
        let old = Goals(calorieGoal: 2000, proteinGoal: 150, fatGoal: 70, carbGoal: 200, stepsGoal: 10_000)
        let kv = isolatedStore("effective-today-2")
        kv.setValue(old, forKey: "@gains/nutrition/goals")
        let versioned = NutritionStore(store: kv)

        let new = Goals(calorieGoal: 1500, proteinGoal: 300, fatGoal: 50, carbGoal: 100, stepsGoal: 10_000)
        versioned.setGoals(new)

        let cal = Calendar.current
        let yesterday = NutritionStore.dayKey(cal.date(byAdding: .day, value: -1, to: Date())!)
        let today = NutritionStore.dayKey(Date())
        XCTAssertEqual(versioned.goals(on: yesterday).calorieGoal, 2000, "yesterday keeps the old goals")
        XCTAssertEqual(versioned.goals(on: today).calorieGoal, 1500, "today gets the new goals")
        _ = store
    }

    func testStreakSurvivesAGoalChangeThatWouldRewriteHistory() {
        let old = Goals(calorieGoal: 2000, proteinGoal: 150, fatGoal: 70, carbGoal: 200, stepsGoal: 10_000)
        let kv = isolatedStore("streak-freeze")
        kv.setValue(old, forKey: "@gains/nutrition/goals")
        let store = NutritionStore(store: kv)

        store.mirrorJournal([FoodJournalEntry(
            foodText: "meal",
            items: [LoggedFoodItem(name: "meal", calories: 1800, proteinG: 160, carbsG: 0, fatG: 0,
                                   citations: [], confidenceScore: 80)],
            status: .resolved,
            loggedAt: entry(daysAgo: 1, calories: 1800, protein: 160).loggedAt
        )])
        XCTAssertEqual(store.currentStreak, 1, "yesterday hit under the old goals")

        store.setGoals(Goals(calorieGoal: 1500, proteinGoal: 300, fatGoal: 50, carbGoal: 100, stepsGoal: 10_000))

        XCTAssertEqual(store.currentStreak, 1,
                       "the streak must survive, yesterday is judged against YESTERDAY's goals")
    }

    func testAutoAdjustRederivesFromCurrentWeightOnlyWhenEnabled() {
        let store = NutritionStore(store: isolatedStore("auto"))

        let before = store.goals
        store.autoAdjustGoals(profile: baseProfile)
        XCTAssertEqual(store.goals, before, "no recipe + switch off = strict no-op")

        store.setGoalRecipe(GoalRecipe(activity: "moderate", direction: "cut"), autoAdjust: true)
        store.autoAdjustGoals(profile: baseProfile)
        let expected = GoalCalculator.estimate(
            profile: baseProfile, activity: .moderate, goal: .cut
        )
        XCTAssertEqual(store.goals.calorieGoal, Double(expected.calorieGoal))
        XCTAssertEqual(store.goals.proteinGoal, Double(expected.proteinGoal))
        XCTAssertEqual(store.goals.stepsGoal, before.stepsGoal, "steps goal is preserved")

        var lighter = baseProfile
        lighter.weightKg = 88.4
        store.autoAdjustGoals(profile: lighter)
        let lighterExpected = GoalCalculator.estimate(profile: lighter, activity: .moderate, goal: .cut)
        XCTAssertEqual(store.goals.calorieGoal, Double(lighterExpected.calorieGoal))
        XCTAssertLessThan(store.goals.calorieGoal, Double(expected.calorieGoal),
                          "less body mass = lower derived target")

        store.setGoalRecipe(store.goalRecipe, autoAdjust: false)
        var lightest = baseProfile
        lightest.weightKg = 80
        let frozen = store.goals
        store.autoAdjustGoals(profile: lightest)
        XCTAssertEqual(store.goals, frozen, "switch off = goals frozen")
    }

    func testSameWeightRecalcDoesNotChurnTheTimeline() {
        let store = NutritionStore(store: isolatedStore("no-churn"))
        store.setGoalRecipe(GoalRecipe(activity: "moderate", direction: "maintain"), autoAdjust: true)
        store.autoAdjustGoals(profile: baseProfile)
        let versions = store.goalsTimeline.count
        store.autoAdjustGoals(profile: baseProfile)
        XCTAssertEqual(store.goalsTimeline.count, versions, "an unchanged result writes nothing")
    }
}
