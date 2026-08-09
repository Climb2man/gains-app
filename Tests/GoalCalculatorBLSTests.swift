import XCTest
@testable import Gains

/// Covers the Bigger Leaner Stronger calorie/macro model. These numbers drive every daily target in
/// the app and there is no manual override any more, so an error here is invisible and total.
final class GoalCalculatorBLSTests: XCTestCase {

    /// The live profile: 65.744 kg, 1.7018 m, 32, male — all four values sourced from WHOOP.
    private var profile: Profile {
        Profile(name: nil, sex: .male, ageYears: 32, heightCm: 170.18,
                weightKg: 65.744, createdAt: "2026-01-01T00:00:00.000Z")
    }

    // MARK: pipeline

    /// BMR is unchanged by this rewrite; pinned so a future edit to EnergyMath is caught here too.
    /// 10(65.744) + 6.25(170.18) − 5(32) + 5
    ///   = 657.44 + 1063.625 − 160 + 5 = 1566.065
    private let expectedBmr = 1566.065

    func testBmrMatchesMifflinStJeor() {
        XCTAssertEqual(EnergyMath.computeBmr(profile), expectedBmr, accuracy: 0.01)
    }

    func testTdeeUsesActivityMidpoint() {
        let r = GoalCalculator.estimate(profile: profile, activity: .moderate, goal: .maintain)
        XCTAssertEqual(r.bmr, 1566)
        XCTAssertEqual(Double(r.tdee), expectedBmr * 1.475, accuracy: 1.0)
    }

    func testGoalCaloriesArePercentagesOfTdee() {
        let tdee = Double(GoalCalculator.estimate(profile: profile, activity: .moderate,
                                                  goal: .maintain).tdee)
        let cut = GoalCalculator.estimate(profile: profile, activity: .moderate, goal: .cut)
        let bulk = GoalCalculator.estimate(profile: profile, activity: .moderate, goal: .leanBulk)
        XCTAssertEqual(Double(cut.calorieGoal), tdee * 0.75, accuracy: 2.0)
        XCTAssertEqual(Double(bulk.calorieGoal), tdee * 1.10, accuracy: 2.0)
    }

    // MARK: macros

    /// The core invariant of the new model, and the reason the old rescaling workaround could go:
    /// macros are derived FROM the calorie goal, so they must always add back up to it.
    func testMacrosReconstructTheCalorieGoal() {
        for goal in GoalCalculator.GoalDirection.allCases {
            for activity in GoalCalculator.ActivityLevel.allCases {
                let r = GoalCalculator.estimate(profile: profile, activity: activity, goal: goal)
                let fromMacros = Double(r.proteinGoal) * 4 + Double(r.carbGoal) * 4
                    + Double(r.fatGoal) * 9
                XCTAssertEqual(fromMacros, Double(r.calorieGoal), accuracy: 12,
                               "\(goal.rawValue)/\(activity.rawValue) macros do not sum to calories")
            }
        }
    }

    func testEverySplitSumsToOne() {
        for goal in GoalCalculator.GoalDirection.allCases {
            let s = goal.macroSplit
            XCTAssertEqual(s.protein + s.carb + s.fat, 1.0, accuracy: 0.0001, goal.rawValue)
        }
    }

    /// The splits change per goal — the previous model applied one split to every goal.
    func testSplitsDifferByGoal() {
        XCTAssertEqual(GoalCalculator.GoalDirection.cut.macroSplit.protein, 0.40, accuracy: 0.0001)
        XCTAssertEqual(GoalCalculator.GoalDirection.maintain.macroSplit.protein, 0.30, accuracy: 0.0001)
        XCTAssertEqual(GoalCalculator.GoalDirection.leanBulk.macroSplit.carb, 0.55, accuracy: 0.0001)
    }

    /// Worked example from the spec: TDEE 2,800 → cut 2,100 → 210P / 210C / 47F.
    func testMatchesSpecWorkedExample() {
        let tdee = 2800.0
        let cals = tdee * 0.75
        let s = GoalCalculator.GoalDirection.cut.macroSplit
        XCTAssertEqual(cals, 2100, accuracy: 0.5)
        XCTAssertEqual((cals * s.protein / 4).rounded(), 210)
        XCTAssertEqual((cals * s.carb / 4).rounded(), 210)
        XCTAssertEqual((cals * s.fat / 9).rounded(), 47)
    }

    /// A cut must land below maintenance and a bulk above it, at every activity level.
    func testOrderingHoldsAcrossActivityLevels() {
        for activity in GoalCalculator.ActivityLevel.allCases {
            let cut = GoalCalculator.estimate(profile: profile, activity: activity, goal: .cut)
            let maintain = GoalCalculator.estimate(profile: profile, activity: activity, goal: .maintain)
            let bulk = GoalCalculator.estimate(profile: profile, activity: activity, goal: .leanBulk)
            XCTAssertLessThan(cut.calorieGoal, maintain.calorieGoal, activity.rawValue)
            XCTAssertLessThan(maintain.calorieGoal, bulk.calorieGoal, activity.rawValue)
        }
    }

    func testActivityFactorsAscendAndMatchTheBook() {
        let factors = GoalCalculator.ActivityLevel.allCases.map(\.factor)
        XCTAssertEqual(factors, [1.15, 1.275, 1.475, 1.675, 1.875])
        XCTAssertEqual(factors, factors.sorted())
    }

    // MARK: the small-frame case that broke the old model

    /// The old model derived protein and fat from body weight alone, so a light frame on an
    /// aggressive deficit could end up with macros costing more calories than the entire target
    /// (~700 kcal of protein + fat against a ~277 kcal goal). Percentages make that impossible.
    func testSmallFrameAggressiveDeficitStaysCoherent() {
        let small = Profile(name: nil, sex: .female, ageYears: 25, heightCm: 150,
                            weightKg: 45, createdAt: "2026-01-01T00:00:00.000Z")
        let r = GoalCalculator.estimate(profile: small, activity: .sedentary, goal: .cut)
        XCTAssertGreaterThan(r.calorieGoal, 0)
        XCTAssertGreaterThan(r.carbGoal, 0, "carbs must never be squeezed to zero")
        let fromMacros = Double(r.proteinGoal) * 4 + Double(r.carbGoal) * 4 + Double(r.fatGoal) * 9
        XCTAssertEqual(fromMacros, Double(r.calorieGoal), accuracy: 12)
    }

    // MARK: strain → activity suggestion

    func testStrainSuggestionBoundaries() {
        XCTAssertEqual(GoalCalculator.suggestedActivity(avgDayStrain: 0), .sedentary)
        XCTAssertEqual(GoalCalculator.suggestedActivity(avgDayStrain: 5.9), .sedentary)
        XCTAssertEqual(GoalCalculator.suggestedActivity(avgDayStrain: 6.0), .light)
        XCTAssertEqual(GoalCalculator.suggestedActivity(avgDayStrain: 9.9), .light)
        XCTAssertEqual(GoalCalculator.suggestedActivity(avgDayStrain: 10.0), .moderate)
        XCTAssertEqual(GoalCalculator.suggestedActivity(avgDayStrain: 13.9), .moderate)
        XCTAssertEqual(GoalCalculator.suggestedActivity(avgDayStrain: 14.0), .veryActive)
        XCTAssertEqual(GoalCalculator.suggestedActivity(avgDayStrain: 17.9), .veryActive)
        XCTAssertEqual(GoalCalculator.suggestedActivity(avgDayStrain: 18.0), .extraActive)
        XCTAssertEqual(GoalCalculator.suggestedActivity(avgDayStrain: 21.0), .extraActive)
    }

    /// Strain is never negative in practice, but a garbage value must not crash or wrap around.
    func testStrainSuggestionHandlesOutOfRange() {
        XCTAssertEqual(GoalCalculator.suggestedActivity(avgDayStrain: -1), .sedentary)
        XCTAssertEqual(GoalCalculator.suggestedActivity(avgDayStrain: 99), .extraActive)
    }

}
