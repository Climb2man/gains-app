import XCTest
@testable import Gains

final class CaloriesSupportTests: XCTestCase {

    func testMacroKcalConstants() {
        XCTAssertEqual(CaloriesSupport.kcalPerProteinG, 4, accuracy: 1e-9)
        XCTAssertEqual(CaloriesSupport.kcalPerCarbG, 4, accuracy: 1e-9)
        XCTAssertEqual(CaloriesSupport.kcalPerFatG, 9, accuracy: 1e-9)
    }

    func testFoodQualitiesStayNormalizedAndDescriptive() {
        let totals = FoodDayTotals(calories: 1840, proteinG: 132, carbsG: 180, fatG: 61)
        let qualities = CaloriesSupport.foodQualities(totals)
        XCTAssertFalse(qualities.isEmpty, "a logged day should produce food-quality rows")
        for q in qualities {
            XCTAssertGreaterThanOrEqual(q.score, 0)
            XCTAssertLessThanOrEqual(q.score, 1)
            XCTAssertFalse(q.label.isEmpty)
            XCTAssertFalse(q.descriptor.isEmpty)
        }
    }
}
