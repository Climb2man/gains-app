import XCTest
@testable import Gains

/// Covers the WHOOP → weight path, which is now the app's ONLY weight source (HealthKit cannot be
/// provisioned on a free Apple ID and manual entry has been removed). A silent failure here means
/// the weight trend and every calorie goal derived from it are wrong with nothing to fall back on.
final class WhoopBodyMeasurementTests: XCTestCase {

    private func json(_ s: String) -> JSONValue { JSONValue.decode(Data(s.utf8)) }

    // MARK: projectBodyMeasurement

    /// The verbatim payload `/developer/v2/user/measurement/body` returned for the live account.
    func testParsesRealPayload() {
        let raw = json(#"{"height_meter":1.7018,"weight_kilogram":65.744,"max_heart_rate":194}"#)
        let m = WhoopProjections.projectBodyMeasurement(raw)
        XCTAssertEqual(m?.weightKg ?? 0, 65.744, accuracy: 0.0001)
        XCTAssertEqual(m?.heightMeters ?? 0, 1.7018, accuracy: 0.0001)
        XCTAssertEqual(m?.maxHeartRate, 194)
    }

    /// THE important case. WHOOP's secondary account (custom:account_id) answers `weight: 0.0`, as
    /// does any account with nothing stored. Adopting it would log a 0 lb weigh-in and feed 0 into
    /// the BMR maths, so it must be rejected outright rather than passed through.
    func testRejectsZeroWeight() {
        let raw = json(#"{"height_meter":1.7018,"weight_kilogram":0.0,"max_heart_rate":194}"#)
        XCTAssertNil(WhoopProjections.projectBodyMeasurement(raw))
    }

    func testRejectsNegativeAndMissingWeight() {
        XCTAssertNil(WhoopProjections.projectBodyMeasurement(json(#"{"weight_kilogram":-5}"#)))
        XCTAssertNil(WhoopProjections.projectBodyMeasurement(json(#"{"height_meter":1.7}"#)))
        XCTAssertNil(WhoopProjections.projectBodyMeasurement(json("{}")))
    }

    /// Weight alone is enough — height and max HR are optional and must not block the weigh-in.
    func testWeightOnlyStillProjects() {
        let m = WhoopProjections.projectBodyMeasurement(json(#"{"weight_kilogram":80.5}"#))
        XCTAssertEqual(m?.weightKg ?? 0, 80.5, accuracy: 0.0001)
        XCTAssertNil(m?.heightMeters)
        XCTAssertNil(m?.maxHeartRate)
    }

    /// Zero height / max HR are absent-in-disguise, not real values; they must come through as nil
    /// so callers don't render "0.0 m" or seed a 0 bpm max.
    func testZeroOptionalsBecomeNil() {
        let m = WhoopProjections.projectBodyMeasurement(
            json(#"{"weight_kilogram":70,"height_meter":0,"max_heart_rate":0}"#))
        XCTAssertNotNil(m)
        XCTAssertNil(m?.heightMeters)
        XCTAssertNil(m?.maxHeartRate)
    }

    // MARK: round-trip

    /// The sync stores kg by way of pounds (`logWeight(lb:)` → `WeightStore.log` → kg), so the value
    /// makes a kg→lb→kg round trip. The de-dup check compares against a 0.005 kg (5 g) tolerance, so
    /// the conversion error has to stay far below that or every sync would log a redundant entry.
    func testKgPoundRoundTripStaysWithinDedupeTolerance() {
        for kg in [65.744, 0.1, 45.0, 120.6, 199.999] {
            let round = Units.lbToKg(Units.kgToLb(kg))
            XCTAssertEqual(round, kg, accuracy: 0.0005,
                           "kg→lb→kg drifted too far for \(kg)")
            XCTAssertLessThan(abs(round - kg), 0.005,
                              "drift would defeat the sync de-dup guard for \(kg)")
        }
    }

    /// Guards the displayed number: 65.744 kg is 144.9 lb, which is what the weight card shows.
    func testLivePayloadConvertsToExpectedPounds() {
        XCTAssertEqual(Units.kgToLb(65.744), 144.94, accuracy: 0.02)
    }
}
