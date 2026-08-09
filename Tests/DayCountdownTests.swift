import XCTest
@testable import Gains

/// The countdown is small, but it is wrong in ways that are easy to ship and hard to notice: a date
/// that reads "Today" for months, or a number that flips at midday instead of midnight.
final class DayCountdownTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func config(_ target: Date, label: String = "") -> CountdownConfig {
        CountdownConfig(targetDate: target, label: label)
    }

    // MARK: day maths

    func testCountsWholeDaysAhead() {
        let c = config(date(2026, 9, 1))
        XCTAssertEqual(c.daysRemaining(from: date(2026, 8, 9), calendar: cal), 23)
    }

    /// The bug this pins: comparing elapsed hours would make tomorrow drop to 0 at midday. Compared
    /// start-of-day to start-of-day, it stays 1 from just after midnight to just before the next.
    func testTomorrowIsOneAllDay() {
        let c = config(date(2026, 8, 10))
        for hour in [0, 6, 12, 18, 23] {
            XCTAssertEqual(c.daysRemaining(from: date(2026, 8, 9, hour), calendar: cal), 1,
                           "should still read 1 day at \(hour):00")
        }
    }

    func testTargetDayIsZeroAllDay() {
        let c = config(date(2026, 8, 9))
        for hour in [0, 9, 23] {
            XCTAssertEqual(c.daysRemaining(from: date(2026, 8, 9, hour), calendar: cal), 0)
        }
    }

    /// The other bug this pins: clamping at 0 made a target from last March read "Today" forever.
    /// It must go negative so the view can hide itself.
    func testPastDatesGoNegative() {
        let c = config(date(2026, 8, 1))
        XCTAssertEqual(c.daysRemaining(from: date(2026, 8, 9), calendar: cal), -8)
    }

    func testCrossesMonthAndYearBoundaries() {
        XCTAssertEqual(config(date(2027, 1, 1)).daysRemaining(from: date(2026, 12, 25), calendar: cal), 7)
        XCTAssertEqual(config(date(2026, 3, 1)).daysRemaining(from: date(2026, 2, 25), calendar: cal), 4)
    }

    /// 2028 is a leap year: February has 29 days, so the gap must be 5 not 4.
    func testLeapYear() {
        XCTAssertEqual(config(date(2028, 3, 1)).daysRemaining(from: date(2028, 2, 25), calendar: cal), 5)
    }

    // MARK: wording

    func testSuffixWithLabel() {
        XCTAssertEqual(DayCountdownStrip.suffix(days: 24, label: "Trip"), "days to Trip")
        XCTAssertEqual(DayCountdownStrip.suffix(days: 1, label: "Trip"), "day to Trip")
    }

    /// The label is optional, so the sentence must not end up as a dangling "24 days to".
    func testSuffixWithoutLabel() {
        XCTAssertEqual(DayCountdownStrip.suffix(days: 24, label: ""), "days left")
        XCTAssertEqual(DayCountdownStrip.suffix(days: 1, label: ""), "day left")
        XCTAssertEqual(DayCountdownStrip.suffix(days: 0, label: ""), "is the day")
    }

    /// A label of only spaces is the same as no label.
    func testWhitespaceLabelTreatedAsEmpty() {
        XCTAssertEqual(DayCountdownStrip.suffix(days: 5, label: "   "), "days left")
        XCTAssertEqual(DayCountdownStrip.accessibilityText(days: 5, label: "  "),
                       "5 days to your target date")
    }

    func testSingularAndPluralInAccessibilityText() {
        XCTAssertEqual(DayCountdownStrip.accessibilityText(days: 1, label: "Trip"), "1 day to Trip")
        XCTAssertEqual(DayCountdownStrip.accessibilityText(days: 3, label: "Trip"), "3 days to Trip")
        XCTAssertEqual(DayCountdownStrip.accessibilityText(days: 0, label: "Trip"), "Today is Trip")
    }
}
