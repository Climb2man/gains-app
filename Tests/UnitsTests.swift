import XCTest
@testable import Gains

final class UnitsTests: XCTestCase {

    func testKgToLb() {
        XCTAssertEqual(Units.kgToLb(100), 220.46226, accuracy: 1e-5)
    }

    func testLbToKgRoundTrips() {
        XCTAssertEqual(Units.lbToKg(Units.kgToLb(80)), 80, accuracy: 1e-9)
    }

    func testFtInToCm() {
        XCTAssertEqual(Units.ftInToCm(feet: 5, inches: 10), 177.8, accuracy: 1e-9)
    }

    func testCmToFtIn() {
        let h = Units.cmToFtIn(177.8)
        XCTAssertEqual(h.feet, 5)
        XCTAssertEqual(h.inches, 10)
    }

    func testCmToFtInCarriesTwelveInches() {
        let h = Units.cmToFtIn(182.88)
        XCTAssertEqual(h.feet, 6)
        XCTAssertEqual(h.inches, 0)
    }
}
