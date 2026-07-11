import XCTest
@testable import Gains

final class GoalPaceMathTests: XCTestCase {

    func testTrendWeightEmptyInput() {
        XCTAssertEqual(GoalPaceMath.trendWeight([]), [])
    }

    func testTrendWeightSeedsWithFirstReading() {
        XCTAssertEqual(GoalPaceMath.trendWeight([200]), [200])
    }

    func testTrendWeightEWMAStep() {
        let trend = GoalPaceMath.trendWeight([200, 190], alpha: 0.10)
        XCTAssertEqual(trend.count, 2)
        XCTAssertEqual(trend[0], 200, accuracy: 1e-9)
        XCTAssertEqual(trend[1], 199, accuracy: 1e-9)
    }

    func testActualRateOverWindow() {
        let trend = [200.0, 199, 198, 197, 196, 195, 194, 193]
        XCTAssertEqual(GoalPaceMath.actualRateLbPerWeek(trend: trend, windowDays: 14), -7, accuracy: 1e-9)
    }

    func testActualRateTooFewPointsIsFlat() {
        XCTAssertEqual(GoalPaceMath.actualRateLbPerWeek(trend: [200]), 0, accuracy: 1e-9)
    }

    func testRequiredRate() {
        XCTAssertEqual(
            GoalPaceMath.requiredRateLbPerWeek(currentTrend: 200, targetWeight: 180, daysUntilTarget: 70),
            -2, accuracy: 1e-9)
    }

    func testStatusOnTrackWithinTolerance() {
        XCTAssertEqual(GoalPaceMath.status(actual: -2, required: -2, remaining: -20), .onTrack)
    }

    func testStatusAhead() {
        XCTAssertEqual(GoalPaceMath.status(actual: -3, required: -2, remaining: -20), .ahead)
    }

    func testStatusBehindWhenTooSlow() {
        XCTAssertEqual(GoalPaceMath.status(actual: -0.5, required: -2, remaining: -20), .behind)
    }

    func testStatusBehindWhenMovingWrongWay() {
        XCTAssertEqual(GoalPaceMath.status(actual: 1, required: -2, remaining: -20), .behind)
    }

    func testProjectedWeeks() throws {
        let weeks = try XCTUnwrap(
            GoalPaceMath.projectedWeeksToGoal(currentTrend: 200, targetWeight: 180, actualRate: -2))
        XCTAssertEqual(weeks, 10, accuracy: 1e-9)
    }

    func testProjectionNilWhenTrendFlat() {
        XCTAssertNil(GoalPaceMath.projectedWeeksToGoal(currentTrend: 200, targetWeight: 180, actualRate: 0.01))
    }

    func testProjectionNilWhenMovingWrongWay() {
        XCTAssertNil(GoalPaceMath.projectedWeeksToGoal(currentTrend: 200, targetWeight: 180, actualRate: 1))
    }

    func testDataConfidenceOkWithEnoughData() {
        XCTAssertEqual(GoalPaceMath.dataConfidence(weighInCount: 28, spanDays: 28, runwayDays: 70), .ok)
    }

    func testDataConfidenceFailsOnTooFewWeighIns() {
        XCTAssertEqual(GoalPaceMath.dataConfidence(weighInCount: 5, spanDays: 28, runwayDays: 70), .notEnoughData)
    }

    func testDataConfidenceFailsOnShortSpan() {
        XCTAssertEqual(GoalPaceMath.dataConfidence(weighInCount: 28, spanDays: 10, runwayDays: 70), .notEnoughData)
    }

    func testDataConfidenceFailsOnShortRunway() {
        XCTAssertEqual(GoalPaceMath.dataConfidence(weighInCount: 28, spanDays: 28, runwayDays: 5), .notEnoughData)
    }

    func testAggressiveTargetByAbsoluteRate() {
        XCTAssertTrue(GoalPaceMath.isAggressiveTarget(requiredRateLbPerWeek: -2.5, currentBodyWeightLb: 200))
    }

    func testAggressiveTargetByPercentOfBodyWeight() {
        XCTAssertTrue(GoalPaceMath.isAggressiveTarget(requiredRateLbPerWeek: -1.5, currentBodyWeightLb: 120))
    }

    func testNotFlaggedWhenWithinGuidelines() {
        XCTAssertFalse(GoalPaceMath.isAggressiveTarget(requiredRateLbPerWeek: -1, currentBodyWeightLb: 200))
    }
}
