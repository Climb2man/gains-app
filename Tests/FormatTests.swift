import XCTest
@testable import Gains

final class FormatTests: XCTestCase {

    func testIntRoundsAndGroupsThousands() {
        XCTAssertEqual(Format.int(1850), "1,850")
        XCTAssertEqual(Format.int(1849.6), "1,850")
        XCTAssertEqual(Format.int(0), "0")
    }

    func testOneDecimalDropsTrailingZero() {
        XCTAssertEqual(Format.oneDecimal(72.0), "72")
        XCTAssertEqual(Format.oneDecimal(71.6), "71.6")
        XCTAssertEqual(Format.oneDecimal(71.96), "72")
    }

    func testWeightRendersPoundsNeverKg() {
        let s = Format.weightLb(80)
        XCTAssertTrue(s.hasSuffix(" lb"))
        XCTAssertFalse(s.localizedCaseInsensitiveContains("kg"))
    }

    func testFeetInchesNeverRendersCm() {
        XCTAssertEqual(Format.feetInches(177.8), "5'10\"")
        XCTAssertEqual(Format.feetInches(182.88), "6'0\"")
    }

    func testDeltaBadgeSignsAndDirections() {
        let up = Format.deltaBadge(5, format: Format.int)
        XCTAssertEqual(up.value, "+5")
        guard case .up = up.direction else { return XCTFail("expected .up") }

        let down = Format.deltaBadge(-5, format: Format.int)
        XCTAssertEqual(down.value, "\u{2212}5")
        guard case .down = down.direction else { return XCTFail("expected .down") }

        let flat = Format.deltaBadge(0, format: Format.int)
        guard case .flat = flat.direction else { return XCTFail("expected .flat") }
    }

    func testShortDayLabel() {
        XCTAssertEqual(Format.shortDayLabel("2026-06-07"), "Sun 7")
    }

    func testShortDayLabelPassesThroughGarbage() {
        XCTAssertEqual(Format.shortDayLabel("not-a-date"), "not-a-date")
    }

    func testTimeLabelParsesBothISOFormsAndKeepsHmmA() {
        let withFraction = Format.timeLabel("2026-06-07T08:12:34.567Z")
        let plain = Format.timeLabel("2026-06-07T08:12:34Z")
        XCTAssertFalse(withFraction.isEmpty, "fractional-seconds ISO must parse")
        XCTAssertFalse(plain.isEmpty, "plain ISO must parse")
        XCTAssertEqual(withFraction, plain, "same minute → same label (seconds dropped)")
        XCTAssertTrue(plain.contains(":"))
        XCTAssertTrue(plain.localizedCaseInsensitiveContains("AM") || plain.localizedCaseInsensitiveContains("PM"))
    }

    func testTimeLabelReturnsEmptyOnGarbage() {
        XCTAssertEqual(Format.timeLabel("not-a-timestamp"), "")
        XCTAssertEqual(Format.timeLabel(""), "")
    }
}
