import XCTest
@testable import Gains

final class CorrelationMathTests: XCTestCase {

    func testPerfectPositiveCorrelation() throws {
        let result = try XCTUnwrap(CorrelationMath.pearson([1, 2, 3, 4], [2, 4, 6, 8]))
        XCTAssertEqual(result.r, 1, accuracy: 1e-9)
        XCTAssertEqual(result.n, 4)
    }

    func testPerfectNegativeCorrelation() throws {
        let result = try XCTUnwrap(CorrelationMath.pearson([1, 2, 3, 4], [8, 6, 4, 2]))
        XCTAssertEqual(result.r, -1, accuracy: 1e-9)
    }

    func testZeroVarianceColumnReturnsNil() {
        XCTAssertNil(CorrelationMath.pearson([5, 5, 5], [1, 2, 3]))
    }

    func testMismatchedLengthsReturnNil() {
        XCTAssertNil(CorrelationMath.pearson([1, 2], [1, 2, 3]))
    }

    func testTooFewPointsReturnsNil() {
        XCTAssertNil(CorrelationMath.pearson([1], [2]))
    }

    func testResultStaysInUnitRange() throws {
        let result = try XCTUnwrap(CorrelationMath.pearson([10, 20, 30], [10, 20, 30]))
        XCTAssertLessThanOrEqual(result.r, 1)
        XCTAssertGreaterThanOrEqual(result.r, -1)
    }

    func testLaggedPairsTodayWithTomorrow() throws {
        let result = try XCTUnwrap(CorrelationMath.laggedPearson(x: [1, 2, 3, 4], y: [99, 1, 2, 3]))
        XCTAssertEqual(result.r, 1, accuracy: 1e-9)
        XCTAssertEqual(result.n, 3)
    }

    func testStrongCorrelationWithLargeNIsSignificant() {
        XCTAssertTrue(CorrelationMath.isSignificant(r: 0.9, n: 21))
    }

    func testWeakCorrelationIsNotSignificant() {
        XCTAssertFalse(CorrelationMath.isSignificant(r: 0.1, n: 10))
    }

    func testTooFewPointsNeverSignificant() {
        XCTAssertFalse(CorrelationMath.isSignificant(r: 0.99, n: 2))
    }

    func testDescriptorBands() {
        XCTAssertEqual(CorrelationMath.describe(r: 0.7), "a strong positive pattern")
        XCTAssertEqual(CorrelationMath.describe(r: -0.4), "a moderate negative pattern")
        XCTAssertEqual(CorrelationMath.describe(r: 0.2), "a weak positive pattern")
        XCTAssertEqual(CorrelationMath.describe(r: 0.05), "almost no pattern")
    }
}
