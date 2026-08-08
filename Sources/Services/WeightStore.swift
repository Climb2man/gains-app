import Foundation
import Observation

@MainActor
@Observable
final class WeightStore {
    private static let storageKey = "@gains/weight/entries"

    /// All weigh-ins, oldest → newest by day.
    private(set) var entries: [WeightEntry] = []

    /// Fired after any mutation so observers can re-sync dependent state.
    @ObservationIgnored var didChange: (() -> Void)?

    private let store: any KeyValueStore

    init(store: any KeyValueStore = EncryptedFileStore.shared) {
        self.store = store
        load()
    }

    func load() {
        entries = (store.value([WeightEntry].self, forKey: Self.storageKey) ?? [])
            .sorted { $0.date < $1.date }
    }

    /// Record a weigh-in (lb). Replaces any existing entry for the same local day.
    @discardableResult
    func log(lb: Double, on date: Date = Date(), bodyFatPct: Double? = nil) -> WeightEntry {
        let key = FoodLogStore.dayKey(date)
        entries.removeAll { $0.date == key }
        let entry = WeightEntry(date: key, kg: Units.lbToKg(lb), bodyFatPct: bodyFatPct)
        entries.append(entry)
        entries.sort { $0.date < $1.date }
        persist()
        return entry
    }

    func remove(id: String) {
        entries.removeAll { $0.id == id }
        persist()
    }

    /// Back-fill the trend from Apple Health weigh-ins. One entry per local day; a day that already
    /// has an entry (a manual log or a prior import) is left untouched, so this is idempotent and
    /// never clobbers a hand-logged value. Returns how many new days were added (0 skips the persist).
    /// Display only. The canonical profile weight keeps its separate confirm-before-write flow.
    @discardableResult
    func importHealthSamples(_ samples: [WeightSampleKg]) -> Int {
        guard !samples.isEmpty else { return 0 }
        var existingDays = Set(entries.map(\.date))
        var byDay: [String: WeightSampleKg] = [:]
        for sample in samples {
            let key = FoodLogStore.dayKey(sample.date)
            if let current = byDay[key], current.date >= sample.date { continue }
            byDay[key] = sample
        }
        var added = 0
        for (key, sample) in byDay where !existingDays.contains(key) {
            entries.append(WeightEntry(date: key, kg: sample.kg))
            existingDays.insert(key)
            added += 1
        }
        guard added > 0 else { return 0 }
        entries.sort { $0.date < $1.date }
        persist()
        return added
    }

    /// The most recent weigh-in in lb, or nil if none logged.
    var latestLb: Double? { entries.last.map { Units.kgToLb($0.kg) } }

    /// Mean weight (kg) over the last `days` calendar days, or nil when the window is empty.
    ///
    /// Goal calories are computed from this rather than the newest reading. A smart scale pushes a
    /// figure to WHOOP most mornings and day-to-day noise (hydration, food in transit) is easily a
    /// pound or two — recomputing targets off a single reading would jitter them daily for no
    /// physiological reason. Averaging, then refreshing weekly, keeps the numbers steady.
    func averageKg(days: Int = 7) -> Double? {
        let window = windowedEntries(days: days)
        guard !window.isEmpty else { return nil }
        return window.reduce(0) { $0 + $1.kg } / Double(window.count)
    }

    /// All weigh-ins as lb values, oldest → newest.
    var allLb: [Double] { entries.map { Units.kgToLb($0.kg) } }

    /// Weigh-ins from the last `days` calendar days, as lb values, oldest → newest.
    func historyLb(days: Int) -> [Double] {
        windowedEntries(days: days).map { Units.kgToLb($0.kg) }
    }

    /// Net change (lb) across the last `days`: latest minus the oldest in the window. nil if < 2 points.
    func changeLb(days: Int) -> Double? {
        let window = windowedEntries(days: days)
        guard let first = window.first, let last = window.last, window.count >= 2 else { return nil }
        return Units.kgToLb(last.kg) - Units.kgToLb(first.kg)
    }

    private func windowedEntries(days: Int) -> [WeightEntry] {
        guard days > 0, let cutoff = Calendar.current.date(byAdding: .day, value: -(days - 1), to: Date())
        else { return entries }
        let cutoffKey = FoodLogStore.dayKey(cutoff)
        return entries.filter { $0.date >= cutoffKey }
    }

    private func persist() {
        store.setValue(entries, forKey: Self.storageKey)
        didChange?()
    }
}
