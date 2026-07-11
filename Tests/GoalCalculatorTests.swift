import XCTest
@testable import Gains

final class GoalCalculatorTests: XCTestCase {

    private func input(
        activity: GoalCalculator.ActivityLevel,
        goal: GoalCalculator.GoalDirection
    ) -> GoalCalculator.Input {
        GoalCalculator.Input(sex: .male, ageYears: 30, heightCm: 180, weightKg: 80,
                             bodyWeightLb: 176, activity: activity, goal: goal)
    }

    func testTdeeIsBmrTimesActivityFactor() {
        let r = GoalCalculator.estimate(input(activity: .moderate, goal: .maintain))
        XCTAssertEqual(r.bmr, 1780)
        XCTAssertEqual(r.tdee, 2759)
    }

    func testMaintainGoalEqualsTdee() {
        let r = GoalCalculator.estimate(input(activity: .moderate, goal: .maintain))
        XCTAssertEqual(r.calorieGoal, r.tdee)
    }

    func testLoseGoalAppliesDelta() {
        let r = GoalCalculator.estimate(input(activity: .moderate, goal: .lose1))
        XCTAssertEqual(r.calorieGoal, 2259)
    }

    func testCalorieGoalNeverNegative() {
        let r = GoalCalculator.estimate(GoalCalculator.Input(
            sex: .female, ageYears: 70, heightCm: 150, weightKg: 40,
            bodyWeightLb: 88, activity: .sedentary, goal: .lose2))
        XCTAssertGreaterThanOrEqual(r.calorieGoal, 0)
    }

    /// Regression: the macro targets must be satisfiable within the calorie target. Protein and fat are
    /// derived from body weight and used to ignore `calorieGoal` entirely, so a light frame on an
    /// aggressive deficit got macros worth more than twice its whole day's calories.
    func testMacrosNeverExceedTheCalorieGoal() {
        for goal in [GoalCalculator.GoalDirection.lose2, .lose1, .lose0_5, .maintain, .gain1] {
            for activity in [GoalCalculator.ActivityLevel.sedentary, .moderate] {
                let r = GoalCalculator.estimate(GoalCalculator.Input(
                    sex: .female, ageYears: 45, heightCm: 152, weightKg: 50,
                    bodyWeightLb: 110, activity: activity, goal: goal))
                let macroCals = Double(r.proteinGoal) * 4 + Double(r.fatGoal) * 9 + Double(r.carbGoal) * 4
                // Each macro is reported as whole grams, so rounding all three up can add ~8.5 kcal
                // (2 + 4.5 + 2). The slack covers that and nothing more: the bug this pins overshot by
                // hundreds of kcal, not single digits.
                XCTAssertLessThanOrEqual(macroCals, Double(r.calorieGoal) + 9,
                                         "\(goal)/\(activity): macros worth \(macroCals) kcal against a \(r.calorieGoal) kcal goal")
            }
        }
    }

    /// The squeeze keeps the protein-to-fat ratio rather than starving one of them.
    func testSqueezedMacrosPreserveTheProteinToFatRatio() {
        let r = GoalCalculator.estimate(GoalCalculator.Input(
            sex: .female, ageYears: 45, heightCm: 152, weightKg: 50,
            bodyWeightLb: 110, activity: .sedentary, goal: .lose2))
        XCTAssertGreaterThan(r.proteinGoal, 0)
        XCTAssertGreaterThan(r.fatGoal, 0)
        // 0.8 g/lb protein against 0.35 g/lb fat, so protein stays a shade over twice the fat.
        XCTAssertEqual(Double(r.proteinGoal) / Double(r.fatGoal), 0.8 / 0.35, accuracy: 0.15)
    }

    /// A normal profile is untouched by the squeeze: it only engages when the weight-derived macros
    /// genuinely do not fit.
    func testTypicalProfileMacrosAreUnscaled() {
        let r = GoalCalculator.estimate(input(activity: .moderate, goal: .maintain))
        XCTAssertEqual(r.proteinGoal, Int((176.0 * 0.8).rounded()))
        XCTAssertEqual(r.fatGoal, Int((176.0 * 0.35).rounded()))
        XCTAssertGreaterThan(r.carbGoal, 0)
    }

    func testMacrosArePositive() {
        let r = GoalCalculator.estimate(input(activity: .moderate, goal: .maintain))
        XCTAssertGreaterThan(r.proteinGoal, 0)
        XCTAssertGreaterThan(r.fatGoal, 0)
        XCTAssertGreaterThanOrEqual(r.carbGoal, 0)
    }

    func testActivityFactors() {
        XCTAssertEqual(GoalCalculator.ActivityLevel.sedentary.factor, 1.2, accuracy: 1e-9)
        XCTAssertEqual(GoalCalculator.ActivityLevel.moderate.factor, 1.55, accuracy: 1e-9)
        XCTAssertEqual(GoalCalculator.ActivityLevel.veryActive.factor, 1.9, accuracy: 1e-9)
    }

    func testGoalDeltas() {
        XCTAssertEqual(GoalCalculator.GoalDirection.lose1.delta, -500, accuracy: 1e-9)
        XCTAssertEqual(GoalCalculator.GoalDirection.maintain.delta, 0, accuracy: 1e-9)
        XCTAssertEqual(GoalCalculator.GoalDirection.gain0_5.delta, 250, accuracy: 1e-9)
    }
}
