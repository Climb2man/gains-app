import XCTest
@testable import Gains

final class EnergyMathTests: XCTestCase {

    func testBmrMale() {
        let bmr = EnergyMath.computeBmr(.init(sex: .male, ageYears: 30, heightCm: 180, weightKg: 80))
        XCTAssertEqual(bmr, 1780, accuracy: 1e-9)
    }

    func testBmrFemale() {
        let bmr = EnergyMath.computeBmr(.init(sex: .female, ageYears: 30, heightCm: 180, weightKg: 80))
        XCTAssertEqual(bmr, 1614, accuracy: 1e-9)
    }

    func testBmrOther() {
        let bmr = EnergyMath.computeBmr(.init(sex: .other, ageYears: 30, heightCm: 180, weightKg: 80))
        XCTAssertEqual(bmr, 1697, accuracy: 1e-9)
    }

    func testBmrScalesWithWeight() {
        let lighter = EnergyMath.computeBmr(.init(sex: .male, ageYears: 30, heightCm: 180, weightKg: 80))
        let heavier = EnergyMath.computeBmr(.init(sex: .male, ageYears: 30, heightCm: 180, weightKg: 90))
        XCTAssertEqual(heavier - lighter, 100, accuracy: 1e-9)
    }
}
