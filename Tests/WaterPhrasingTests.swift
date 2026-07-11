import XCTest
@testable import Gains

final class WaterPhrasingTests: XCTestCase {

    func testPlainWaterIsWaterWithNoVolume() {
        let r = WaterPhrasing.parse("water")
        XCTAssertTrue(r.isWater)
        XCTAssertNil(r.milliliters)
    }

    func testWatermelonIsNotWater() {
        XCTAssertFalse(WaterPhrasing.parse("watermelon").isWater)
    }

    func testCoconutWaterIsNotWater() {
        XCTAssertFalse(WaterPhrasing.parse("coconut water").isWater)
    }

    func testSparklingWaterWithJuiceIsNotWater() {
        XCTAssertFalse(WaterPhrasing.parse("sparkling water with lime juice").isWater)
    }

    func testRealFoodIsNotWater() {
        let r = WaterPhrasing.parse("grilled chicken salad")
        XCTAssertFalse(r.isWater)
        XCTAssertNil(r.milliliters)
    }

    func testOuncesParseToMilliliters() {
        let r = WaterPhrasing.parse("16 oz water")
        XCTAssertTrue(r.isWater)
        XCTAssertEqual(r.milliliters ?? 0, 16 * 29.5735, accuracy: 0.01)
    }

    func testMillilitersParseDirectly() {
        XCTAssertEqual(WaterPhrasing.parse("500 ml water").milliliters, 500)
    }

    func testAGlassDefaultsToAStandardGlass() {
        XCTAssertEqual(WaterPhrasing.parse("a glass of water").milliliters, 240)
    }

    func testNumberedGlassesScale() {
        XCTAssertEqual(WaterPhrasing.parse("2 glasses of water").milliliters, 480)
    }

    func testBottleScales() {
        XCTAssertEqual(WaterPhrasing.parse("1 bottle of water").milliliters, 500)
    }
}
