import Foundation
import HealthKit

/// The `UserDefaults` keys recording the user's Apple Health connection, shared so the onboarding step
/// and the Settings card can't drift. Both are non-PHI booleans:
///   • `weightRequested`: the user asked to connect (consent sheet was shown). A read grant can't be
///     confirmed, so this alone never asserts "connected."
///   • `weightConnected`: a weight was actually read back, which proves read access works. Only this
///     justifies a green "connected" surface.
enum AppleHealthKeys {
    static let weightRequested = "gains.health.weightRequested"
    static let weightConnected = "gains.health.weightConnected"
}

/// One body-mass sample read from Apple Health: when it was taken + the value in kilograms (canonical
/// metric; the UI converts to lb). A plain, Sendable DTO so the history read can cross the actor edge.
struct WeightSampleKg: Sendable {
    let date: Date
    let kg: Double
}

/// The thin protocol the rest of the app depends on (so a swap touches one file). Body-measurement
/// reads only; every reader returns `Double?` and never throws; `nil` means "unavailable."
protocol HealthService: Sendable {
    /// Is HealthKit usable on this device? False on the iOS Simulator (no Health store) and anywhere
    /// the data store is unavailable. Never throws.
    func isAvailable() -> Bool

    /// Ask iOS for read access to body mass. iOS shows the consent sheet at most once per type; we
    /// don't inspect the result to infer the grant (impossible for reads). Returns silently even if the
    /// request fails.
    func requestAuthorization() async

    /// Latest body mass in kilograms (canonical metric), or `nil`. Convert to lb at the display edge.
    func latestWeightKg() async -> Double?
    /// Latest body-fat as a 0–100 percent, or `nil`. (HealthKit stores a 0.0–1.0 fraction, converted here.)
    func latestBodyFatPercent() async -> Double?
    /// Latest height in centimeters (canonical metric), or `nil`.
    func latestHeightCm() async -> Double?
    /// Latest lean body mass in kilograms (canonical metric), or `nil`.
    func latestLeanMassKg() async -> Double?

    /// Every body-mass sample from the last `days` days, oldest → newest. Empty on no-data,
    /// no-permission, or any error (never throws, never logs a value). Backs the weight trend with a
    /// smart scale's full history, vs. `latestWeightKg`'s single point.
    func weightSamplesKg(sinceDays days: Int) async -> [WeightSampleKg]
}

/// The production `HealthService` backed by `HKHealthStore`.
///
/// The body-measurement types Gains can read. Only `readTypes` is requested up front; a query for a
/// type without granted read access returns no data, which the readers map to `nil`.
struct HealthKitService: HealthService {
    private let store = HKHealthStore()

    private static let bodyMass = HKQuantityType(.bodyMass)
    private static let bodyFat = HKQuantityType(.bodyFatPercentage)
    private static let leanMass = HKQuantityType(.leanBodyMass)
    private static let height = HKQuantityType(.height)

    private static let readTypes: Set<HKObjectType> = [bodyMass]

    func isAvailable() -> Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async {
        guard isAvailable() else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: Self.readTypes)
        } catch {
        }
    }

    func latestWeightKg() async -> Double? {
        await readLatest(Self.bodyMass, unit: .gramUnit(with: .kilo))
    }

    func latestBodyFatPercent() async -> Double? {
        guard let fraction = await readLatest(Self.bodyFat, unit: .percent()) else { return nil }
        return fraction * 100
    }

    func latestHeightCm() async -> Double? {
        await readLatest(Self.height, unit: .meterUnit(with: .centi))
    }

    func latestLeanMassKg() async -> Double? {
        await readLatest(Self.leanMass, unit: .gramUnit(with: .kilo))
    }

    func weightSamplesKg(sinceDays days: Int) async -> [WeightSampleKg] {
        guard isAvailable() else { return [] }
        do {
            let start = Calendar.current.date(
                byAdding: .day, value: -max(0, days - 1),
                to: Calendar.current.startOfDay(for: Date())
            )
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(
                    type: Self.bodyMass,
                    predicate: HKQuery.predicateForSamples(withStart: start, end: nil)
                )],
                sortDescriptors: [SortDescriptor(\.endDate, order: .forward)]
            )
            let unit = HKUnit.gramUnit(with: .kilo)
            return try await descriptor.result(for: store).compactMap { sample in
                let kg = sample.quantity.doubleValue(for: unit)
                guard kg.isFinite, kg > 0 else { return nil }
                return WeightSampleKg(date: sample.endDate, kg: kg)
            }
        } catch {
            return []
        }
    }

    /// Read the most-recent sample for `type`, expressed in `unit`. Returns the raw numeric quantity,
    /// or `nil` on no-data, no-permission, or any error. Centralizes the defensive contract so each
    /// public reader is a one-liner. Never logs the value, never throws.
    private func readLatest(_ type: HKQuantityType, unit: HKUnit) async -> Double? {
        guard isAvailable() else { return nil }
        do {
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: type)],
                sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
                limit: 1
            )
            let samples = try await descriptor.result(for: store)
            guard let sample = samples.first else { return nil }
            let value = sample.quantity.doubleValue(for: unit)
            return value.isFinite ? value : nil
        } catch {
            return nil
        }
    }
}
