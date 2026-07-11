import XCTest
@testable import Gains

@MainActor
final class FoodLoggingRouterTests: XCTestCase {

    func testPortionOnlyEditsTakeTheCheapLane() {
        XCTAssertTrue(FoodLoggingRouter.looksPortionOnly(old: "burrito", new: "half a burrito"))
        XCTAssertTrue(FoodLoggingRouter.looksPortionOnly(old: "burrito", new: "a couple bites of burrito"))
        XCTAssertTrue(FoodLoggingRouter.looksPortionOnly(old: "chicken bowl", new: "large chicken bowl"))
        XCTAssertTrue(FoodLoggingRouter.looksPortionOnly(old: "salad", new: "small salad"))
        XCTAssertTrue(FoodLoggingRouter.looksPortionOnly(old: "rice", new: "two servings of rice"))
        XCTAssertTrue(FoodLoggingRouter.looksPortionOnly(old: "double burrito", new: "burrito"))
        XCTAssertTrue(FoodLoggingRouter.looksPortionOnly(old: "eggs", new: "2x eggs"))
    }

    func testCaseAndWhitespaceInsensitive() {
        XCTAssertTrue(FoodLoggingRouter.looksPortionOnly(old: "Burrito", new: "  HALF a Burrito "))
    }

    func testSubstantiveChangesAreNotPortionOnly() {
        XCTAssertFalse(FoodLoggingRouter.looksPortionOnly(old: "burrito", new: "pizza"))
        XCTAssertFalse(FoodLoggingRouter.looksPortionOnly(old: "burrito", new: "chicken burrito"))
        XCTAssertFalse(FoodLoggingRouter.looksPortionOnly(old: "coffee", new: "coffee cake"))
        XCTAssertFalse(FoodLoggingRouter.looksPortionOnly(old: "grilled chicken salad", new: "grilled salmon salad"))
    }

    func testShortWordsDoNotCorruptFoodNames() {
        XCTAssertTrue(FoodLoggingRouter.looksPortionOnly(old: "coffee", new: "large coffee"))
        XCTAssertFalse(FoodLoggingRouter.looksPortionOnly(old: "coffee", new: "tea"))
    }

    func testEmptyOrIdenticalInputsAreFalse() {
        XCTAssertFalse(FoodLoggingRouter.looksPortionOnly(old: "", new: "half a burrito"))
        XCTAssertFalse(FoodLoggingRouter.looksPortionOnly(old: "burrito", new: ""))
        XCTAssertFalse(FoodLoggingRouter.looksPortionOnly(old: "burrito", new: "burrito"))
        XCTAssertFalse(FoodLoggingRouter.looksPortionOnly(old: "  burrito ", new: "burrito"))
    }
}
