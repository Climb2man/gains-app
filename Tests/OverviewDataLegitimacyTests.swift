import XCTest
@testable import Gains

@MainActor
final class OverviewDataLegitimacyTests: XCTestCase {

    func testGoalPaceShowsInTheDemoButNotInAFreshContainer() {
        XCTAssertNotNil(OverviewModel(appModel: .sample).goalPace)
        XCTAssertNil(OverviewModel(appModel: .emptyOnboarded).goalPace)
    }

    func testUsesSampleDataFlagDistinguishesTheContainers() {
        XCTAssertTrue(OverviewModel(appModel: .sample).usesSampleData)
        XCTAssertFalse(OverviewModel(appModel: .emptyOnboarded).usesSampleData)
    }
}
