import XCTest
@testable import Gains

final class FoodAINutritionServiceTests: XCTestCase {

    func testReconcileFixesCaloriesWhenMacrosImplyADifferentTotal() {
        let item = LoggedFoodItem(name: "Bowl", calories: 500, proteinG: 30, carbsG: 40, fatG: 10)
        XCTAssertEqual(FoodAINutritionService.reconciled(item).calories, 370)
    }

    func testReconcileLeavesCaloriesWithinTolerance() {
        let item = LoggedFoodItem(name: "x", calories: 405, proteinG: 30, carbsG: 40, fatG: 10)
        XCTAssertEqual(FoodAINutritionService.reconciled(item).calories, 405)
    }

    func testReconcileRespectsTheAbsoluteKcalFloor() {
        let item = LoggedFoodItem(name: "garnish", calories: 40, proteinG: 1, carbsG: 1, fatG: 1)
        XCTAssertEqual(FoodAINutritionService.reconciled(item).calories, 40)
    }

    func testReconcileNeverTouchesAWaterItem() {
        let water = LoggedFoodItem(name: "Water", calories: 300, proteinG: 10, carbsG: 10, fatG: 10,
                                   isWaterEntry: true)
        XCTAssertEqual(FoodAINutritionService.reconciled(water).calories, 300)
    }

    func testReconcileNoOpWhenEverythingIsZero() {
        let empty = LoggedFoodItem(name: "x", calories: 0, proteinG: 0, carbsG: 0, fatG: 0)
        XCTAssertEqual(FoodAINutritionService.reconciled(empty).calories, 0)
    }

    func testStripFencePassesThroughBareJSON() {
        XCTAssertEqual(FoodAINutritionService.stripFence("{\"a\":1}"), "{\"a\":1}")
    }

    func testStripFenceRemovesAJSONLabelledFence() {
        XCTAssertEqual(FoodAINutritionService.stripFence("```json\n{\"a\":1}\n```"), "{\"a\":1}")
    }

    func testStripFenceRemovesAPlainFenceAndOuterWhitespace() {
        XCTAssertEqual(FoodAINutritionService.stripFence("  ```\n{\"a\":1}\n```  "), "{\"a\":1}")
    }

    private func decodeWire(_ json: String) throws -> NutritionItemWire {
        try JSONDecoder().decode(NutritionItemWire.self, from: Data(json.utf8))
    }

    func testWireDecodesRequiredMacrosAndDefaultsOptionals() throws {
        let wire = try decodeWire(#"{"name":"Eggs","calories":140,"protein":12,"carbs":1,"fat":10}"#)
        let item = wire.asLoggedItem()
        XCTAssertEqual(item.name, "Eggs")
        XCTAssertEqual(item.calories, 140)
        XCTAssertEqual(item.proteinG, 12)
        XCTAssertNil(item.sugarG)
        XCTAssertTrue(item.citations.isEmpty)
    }

    func testWireThrowsWhenARequiredMacroIsMissing() {
        XCTAssertThrowsError(try decodeWire(#"{"name":"Eggs","protein":12,"carbs":1,"fat":10}"#))
    }

    func testWireClampsConfidenceIntoZeroToHundred() throws {
        let high = try decodeWire(#"{"name":"x","calories":100,"protein":1,"carbs":1,"fat":1,"confidenceScore":150}"#)
        XCTAssertEqual(high.asLoggedItem().confidenceScore, 100)
        let low = try decodeWire(#"{"name":"x","calories":100,"protein":1,"carbs":1,"fat":1,"confidenceScore":-5}"#)
        XCTAssertEqual(low.asLoggedItem().confidenceScore, 0)
    }
}
