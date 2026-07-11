import XCTest
@testable import Gains

@MainActor
final class DateStripTests: XCTestCase {

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d
        return Calendar.current.date(from: c)!
    }

    func testToKeyFormatsLocalYYYYMMDD() {
        XCTAssertEqual(DateStrip.toKey(date(2026, 6, 7)), "2026-06-07")
        XCTAssertEqual(DateStrip.toKey(date(2026, 12, 31)), "2026-12-31")
        XCTAssertEqual(DateStrip.toKey(date(2026, 1, 1)), "2026-01-01")
    }

    func testParseKeyDateNumber() {
        XCTAssertEqual(DateStrip.parseKey("2026-06-07").dateNum, 7)
        XCTAssertEqual(DateStrip.parseKey("2026-12-31").dateNum, 31)
    }

    func testParseKeyWeekdayMatchesCalendar() {
        let d = date(2026, 6, 7)
        let expected = Calendar.current.component(.weekday, from: d) - 1
        XCTAssertEqual(DateStrip.parseKey(DateStrip.toKey(d)).weekday, expected)
    }

    func testCurrentWeekKeysAreSevenSundayToSaturday() {
        let keys = DateStrip.currentWeekKeys(containing: date(2026, 6, 10))
        XCTAssertEqual(keys.count, 7)
        XCTAssertEqual(DateStrip.parseKey(keys.first!).weekday, 0, "first cell is Sunday")
        XCTAssertEqual(DateStrip.parseKey(keys.last!).weekday, 6, "last cell is Saturday")
        XCTAssertTrue(keys.contains(DateStrip.toKey(date(2026, 6, 10))), "the week contains its anchor day")
        assertConsecutive(keys)
    }

    func testTrailingKeysEndTodayOldestFirst() {
        let keys = DateStrip.trailingKeys(days: 30)
        XCTAssertEqual(keys.count, 30)
        XCTAssertEqual(keys.last, DateStrip.toKey(Date()), "the range ends today (rightmost cell)")
        assertConsecutive(keys)
    }

    func testTrailingKeysClampsToAtLeastOne() {
        XCTAssertEqual(DateStrip.trailingKeys(days: 0).count, 1)
        XCTAssertEqual(DateStrip.trailingKeys(days: -5).count, 1)
    }

    /// Assert the keys are consecutive calendar days, oldest → newest.
    private func assertConsecutive(_ keys: [String]) {
        let cal = Calendar.current
        let dates = keys.map { key -> Date in
            let p = key.split(separator: "-").compactMap { Int($0) }
            var c = DateComponents(); c.year = p[0]; c.month = p[1]; c.day = p[2]
            return cal.date(from: c)!
        }
        for i in 1..<dates.count {
            XCTAssertEqual(cal.dateComponents([.day], from: dates[i - 1], to: dates[i]).day, 1,
                           "keys must be consecutive days")
        }
    }
}
