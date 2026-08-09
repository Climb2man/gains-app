import XCTest
@testable import Gains

/// The recommender suggests what to eat, so a bad ranking is not cosmetic — it pushes the user past
/// their targets. These pin the behaviour that makes a suggestion trustworthy.
final class MacroGapRecommenderTests: XCTestCase {

    private func food(_ name: String, _ cal: Double, _ p: Double, _ c: Double, _ f: Double)
        -> MacroGapRecommender.Candidate {
        .init(id: name, name: name, calories: cal, proteinG: p, carbsG: c, fatG: f)
    }

    /// 600 kcal / 50P / 60C / 20F still owed.
    private let gap = MacroGapRecommender.Gap(
        calories: 600, proteinG: 50, carbsG: 60, fatG: 20
    )

    func testPicksTheClosestFit() {
        let best = food("chicken and rice", 580, 48, 62, 18)
        let results = MacroGapRecommender.rank(
            candidates: [food("apple", 95, 0, 25, 0), best, food("almonds", 400, 15, 15, 35)],
            gap: gap
        )
        XCTAssertEqual(results.first?.candidate, best)
    }

    /// A food far bigger than the remaining budget must be dropped, not merely ranked last —
    /// suggesting it at all would be wrong.
    func testDropsFoodsThatBlowTheCalorieBudget() {
        let results = MacroGapRecommender.rank(
            candidates: [food("large pizza", 1800, 70, 200, 60), food("yoghurt", 150, 15, 12, 4)],
            gap: gap
        )
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.candidate.name, "yoghurt")
    }

    /// Slightly over is allowed — real food rarely lands exactly — but it is flagged.
    func testSmallOvershootIsAllowedButFlagged() {
        let results = MacroGapRecommender.rank(
            candidates: [food("big bowl", 680, 55, 70, 22)], gap: gap
        )
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].overshoots)
    }

    /// Protein is weighted above carbs and fat, so between two foods of identical calories the one
    /// that closes the protein gap must win.
    func testProteinIsPreferredAtEqualCalories() {
        let lean = food("cottage cheese", 300, 45, 12, 5)
        let carby = food("bagel", 300, 10, 60, 2)
        let results = MacroGapRecommender.rank(candidates: [carby, lean], gap: gap)
        XCTAssertEqual(results.first?.candidate, lean)
    }

    func testReturnsNothingWhenEveryTargetIsMet() {
        let closed = MacroGapRecommender.Gap(calories: 0, proteinG: -5, carbsG: -10, fatG: 0)
        XCTAssertTrue(closed.isClosed)
        XCTAssertTrue(MacroGapRecommender.rank(
            candidates: [food("anything", 100, 10, 10, 1)], gap: closed).isEmpty)
    }

    func testRespectsTheLimit() {
        let many = (1...10).map { food("f\($0)", 200, 20, 20, 5) }
        XCTAssertEqual(MacroGapRecommender.rank(candidates: many, gap: gap, limit: 3).count, 3)
    }

    /// Equal scores must not reshuffle between renders.
    func testTiesAreOrderedStably() {
        let a = food("alpha", 300, 25, 30, 10)
        let b = food("beta", 300, 25, 30, 10)
        let first = MacroGapRecommender.rank(candidates: [b, a], gap: gap)
        let second = MacroGapRecommender.rank(candidates: [a, b], gap: gap)
        XCTAssertEqual(first.map(\.candidate.name), second.map(\.candidate.name))
        XCTAssertEqual(first.first?.candidate.name, "alpha")
    }

    /// Zero-calorie rows (water, a mis-parsed entry) are not food suggestions.
    func testIgnoresZeroCalorieCandidates() {
        let results = MacroGapRecommender.rank(
            candidates: [food("water", 0, 0, 0, 0), food("eggs", 200, 18, 2, 14)], gap: gap
        )
        XCTAssertEqual(results.map(\.candidate.name), ["eggs"])
    }

    /// A macro already passed should steer suggestions away from it: with fat over budget, the
    /// leaner of two otherwise-similar foods must win.
    func testAlreadyPassedMacroPushesSuggestionsAway() {
        let fatOver = MacroGapRecommender.Gap(calories: 500, proteinG: 40, carbsG: 50, fatG: -15)
        let lean = food("turkey breast", 300, 40, 40, 3)
        let fatty = food("cheese plate", 300, 20, 20, 24)
        let results = MacroGapRecommender.rank(candidates: [fatty, lean], gap: fatOver)
        XCTAssertEqual(results.first?.candidate, lean)
    }

    func testGapIsGoalMinusEaten() {
        let goals = Goals(calorieGoal: 2000, proteinGoal: 150, fatGoal: 60, carbGoal: 200,
                          stepsGoal: 8000)
        let totals = DailyTotals(calories: 1400, proteinG: 100, carbsG: 140, fatG: 40)
        let g = MacroGapRecommender.gap(goals: goals, totals: totals)
        XCTAssertEqual(g.calories, 600, accuracy: 0.001)
        XCTAssertEqual(g.proteinG, 50, accuracy: 0.001)
        XCTAssertEqual(g.carbsG, 60, accuracy: 0.001)
        XCTAssertEqual(g.fatG, 20, accuracy: 0.001)
    }
}
