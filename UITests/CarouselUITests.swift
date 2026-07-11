import XCTest

final class CarouselUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = true
    }

    func testCarouselSwipeOnOverview() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleData", "YES", "-initialTab", "overview"]
        app.launch()

        sleep(3)
        attach(app.screenshot(), "1-overview-initial")

        let strip = app.scrollViews["dateStrip"].firstMatch
        XCTAssertTrue(strip.waitForExistence(timeout: 5), "date carousel not found")

        strip.swipeLeft()
        sleep(1)
        attach(app.screenshot(), "2-after-swipe-left")

        strip.swipeRight()
        sleep(1)
        attach(app.screenshot(), "3-after-swipe-right")
    }

    private func attach(_ screenshot: XCUIScreenshot, _ name: String) {
        let att = XCTAttachment(screenshot: screenshot)
        att.name = name
        att.lifetime = .keepAlways
        add(att)
    }
}
