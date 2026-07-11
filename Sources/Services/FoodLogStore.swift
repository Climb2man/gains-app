import Foundation
import Observation

@MainActor
@Observable
final class FoodLogStore {
    private static let entriesKey = "@gains/foodlog/entries"

    /// All logged lines across all days (unsorted, as written). Day views filter + sort.
    private(set) var entries: [FoodJournalEntry] = []

    /// Day key per entry id. `loggedAt` is immutable after insert, so each line's local day is a
    /// constant; caching it turns the per-entry ISO parse in entries(on:)/hasEntries(on:)/totals(on:)
    /// into a dictionary hit. Filled lazily on miss, so wholesale replacements of `entries` (load,
    /// DEBUG seedToday) stay correct without rebuilds. `@ObservationIgnored`: a derived cache, not UI
    /// state, so filling it mid-read must not invalidate the observing view.
    @ObservationIgnored private var dayKeyByID: [String: String] = [:]

    /// Fired after every persisted journal mutation with the full entry list. AppModel wires this to
    /// `NutritionStore.mirrorJournal(_:)` so the dashboard/widget rollups always track the journal, the
    /// single source of truth for logged food. `@ObservationIgnored`: wiring, not UI state.
    @ObservationIgnored var entriesDidChange: (([FoodJournalEntry]) -> Void)?

    private let store: any KeyValueStore
    private let service: any FoodLoggingService
    /// The retry queue: every async fill runs through it, keyed by the line's id, so a fast follow-up
    /// edit supersedes the stale in-flight fill (latest write wins) and a transient failure gets
    /// bounded backoff retries before the offline fallback.
    private let fillQueue: BackgroundTaskQueue

    /// A non-credential, user-facing notice (e.g. "add your key in Settings"). Never holds a key.
    var notice: String?

    init(
        service: any FoodLoggingService,
        store: any KeyValueStore = EncryptedFileStore.shared,
        fillQueue: BackgroundTaskQueue? = nil
    ) {
        self.service = service
        self.store = store
        self.fillQueue = fillQueue ?? BackgroundTaskQueue()
        load()
    }

    private func load() {
        if let stored = store.value([FoodJournalEntry].self, forKey: Self.entriesKey) {
            entries = stored
        }
    }

    private func persist() {
        store.setValue(entries, forKey: Self.entriesKey)
        entriesDidChange?(entries)
    }

    /// The lines logged on `dayKey`'s local day, newest first (a notes list reads top-down newest).
    func entries(on dayKey: String) -> [FoodJournalEntry] {
        entries
            .filter { cachedDayKey(of: $0) == dayKey }
            .sorted { $0.loggedAt > $1.loggedAt }
    }

    /// Whether any line exists on a day; lets the date strip mark logged days.
    func hasEntries(on dayKey: String) -> Bool {
        entries.contains { cachedDayKey(of: $0) == dayKey }
    }

    /// The recent-history feed (the composer's clock button): every resolved, non-water line across all
    /// days, newest first, capped. Real logged meals the user can re-log in one tap; pending/failed
    /// lines (no macros yet) and pure-water lines are excluded so the feed is always re-loggable.
    func recentLines(limit: Int = 60) -> [FoodJournalEntry] {
        entries
            .filter { $0.status == .resolved && !$0.items.isEmpty && !$0.isWaterOnly }
            .sorted { $0.loggedAt > $1.loggedAt }
            .prefix(limit)
            .map { $0 }
    }

    /// The bottom totals bar's sums for a day: calories + P/C/F always; sugar/fiber/sodium
    /// accumulate too (the view shows them only when the toggle is on). Water excluded from calories.
    func totals(on dayKey: String) -> FoodDayTotals {
        var totals = FoodDayTotals.zero
        for entry in entries where cachedDayKey(of: entry) == dayKey {
            for item in entry.items {
                if item.isWaterEntry {
                    totals.waterMilliliters += item.waterMilliliters ?? 0
                    continue
                }
                totals.calories += item.calories
                totals.proteinG += item.proteinG
                totals.carbsG += item.carbsG
                totals.fatG += item.fatG
                totals.sugarG += item.sugarG ?? 0
                totals.fiberG += item.fiberG ?? 0
                totals.sodiumMg += item.sodiumMg ?? 0
            }
        }
        return totals
    }

    /// The entry's local day key via `dayKeyByID`; parses the ISO timestamp once per entry, ever.
    private func cachedDayKey(of entry: FoodJournalEntry) -> String {
        if let key = dayKeyByID[entry.id] { return key }
        let key = Self.dayKey(of: entry)
        dayKeyByID[entry.id] = key
        return key
    }

    /// Log a new natural-language line. Inserts an optimistic `.pending` row immediately (so the UI
    /// never waits), then resolves macros via the pipeline and flips the row to `.resolved`/`.failed`.
    /// Returns the line's id so a caller can scroll to or track it. Set `bias`/`micronutrients` from the
    /// user's settings.
    @discardableResult
    func logLine(
        _ text: String,
        bias: CalorieBias,
        micronutrients: MicronutrientToggles
    ) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = FoodJournalEntry(foodText: trimmed, status: .pending, loggedAt: Self.isoNow())
        entries.append(entry)
        persist()

        enqueueLineResolve(entryID: entry.id, request: FoodLineRequest(
            text: trimmed, bias: bias, micronutrients: micronutrients
        ))
        return entry.id
    }

    /// Log a line resolved from a capture (photo/package/barcode) the user has already reviewed and
    /// confirmed. Inserts a `.resolved` line directly from the confirmed items, with no further AI (the
    /// vision/lookup call already ran, the user edited the numbers). `photoLocalPath` is the on-device
    /// path of the captured image, recorded as provenance so the source stays traceable. Returns the new
    /// line id.
    ///
    /// Safety: these items are the user's confirmed estimate, which is what makes a captured value
    /// canonical. The image path is local provenance only, never uploaded.
    @discardableResult
    func logCapturedLine(
        text: String,
        items: [LoggedFoodItem],
        photoLocalPath: String? = nil
    ) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = items.map { item -> LoggedFoodItem in
            var copy = freshCopy(of: item)
            if let photoLocalPath, !photoLocalPath.isEmpty {
                let note = "Logged from a photo on your device."
                copy.assumptions = copy.assumptions.map { "\($0) \(note)" } ?? note
            }
            return copy
        }
        let entry = FoodJournalEntry(
            foodText: trimmed.isEmpty ? (resolved.first?.name ?? "Logged from photo") : trimmed,
            items: resolved,
            status: .resolved,
            loggedAt: Self.isoNow()
        )
        entries.append(entry)
        persist()
        return entry.id
    }

    /// Re-log a saved shortcut to today in one tap: inserts a `.resolved` line from the saved snapshot,
    /// no AI calls, offline. Returns the new line id.
    @discardableResult
    func logShortcut(_ shortcut: FoodShortcut) -> String {
        let entry = FoodJournalEntry(
            foodText: shortcut.nickname,
            items: shortcut.items.map { freshCopy(of: $0) },
            status: .resolved,
            loggedAt: Self.isoNow()
        )
        entries.append(entry)
        persist()
        return entry.id
    }

    /// Edit an existing line by re-typing it in plain English. Updates the text, flips the
    /// row back to `.pending`, and re-resolves via the cheap portion path when applicable.
    func editLine(
        id: String,
        newText: String,
        bias: CalorieBias,
        micronutrients: MicronutrientToggles
    ) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let oldText = entries[index].foodText
        let existing = entries[index].items
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)

        entries[index].foodText = trimmed
        entries[index].status = .pending
        persist()

        enqueueEditResolve(entryID: id, request: FoodEditRequest(
            oldText: oldText,
            newText: trimmed,
            existingItems: existing,
            bias: bias,
            micronutrients: micronutrients
        ))
    }

    /// Retry a `.failed` line (e.g. after the user added their key). Re-runs the original text.
    func retry(id: String, bias: CalorieBias, micronutrients: MicronutrientToggles) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let text = entries[index].foodText
        entries[index].status = .pending
        persist()
        enqueueLineResolve(entryID: id, request: FoodLineRequest(
            text: text, bias: bias, micronutrients: micronutrients
        ))
    }

    /// Apply a hand-correction to a single resolved item. Recomputes the line and persists. The
    /// corrected line keeps its items (provenance stays honest, user-confirmed).
    func updateItem(entryID: String, item: LoggedFoodItem) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        guard let itemIndex = entries[index].items.firstIndex(where: { $0.id == item.id }) else { return }
        entries[index].items[itemIndex] = item
        entries[index].status = .resolved
        persist()
    }

    /// Delete a logged line (swipe-to-delete in the notes list). Cancels any in-flight fill for it.
    func removeLine(id: String) {
        fillQueue.cancel(token: id)
        entries.removeAll { $0.id == id }
        dayKeyByID[id] = nil
        persist()
    }

    /// Run a new-line resolve through the retry queue. A `.transient` failure retries with backoff;
    /// only after attempts exhaust does the line land the editable, honestly-labeled offline fallback
    /// (never a silent loss). `.missingKey` fails fast (retrying can't conjure a key) to the Settings
    /// notice. Token = line id, so re-running the same line supersedes its stale fill.
    private func enqueueLineResolve(entryID: String, request: FoodLineRequest) {
        fillQueue.enqueue(
            token: entryID,
            operation: { [service] in try await service.resolveLine(request) },
            onSuccess: { [weak self] result in self?.apply(result, to: entryID) },
            onFailure: { [weak self] error in
                if case FoodLoggingError.missingKey = error {
                    self?.markFailed(entryID, notice: Self.missingKeyNotice)
                } else {
                    self?.apply(FoodLineResult(items: [FoodLoggingFallback.offlineItem(text: request.text)]),
                                to: entryID)
                }
            },
            shouldRetry: Self.isRetryableFillError
        )
    }

    /// Run an edit resolve through the retry queue. Same contract as `enqueueLineResolve`, except the
    /// exhausted-retries fallback keeps the line's existing items (better than zeroing), marked honestly
    /// via `FoodLoggingFallback.markFallback`.
    private func enqueueEditResolve(entryID: String, request: FoodEditRequest) {
        fillQueue.enqueue(
            token: entryID,
            operation: { [service] in try await service.resolveEdit(request) },
            onSuccess: { [weak self] result in self?.apply(result, to: entryID) },
            onFailure: { [weak self] error in
                if case FoodLoggingError.missingKey = error {
                    self?.markFailed(entryID, notice: Self.missingKeyNotice)
                } else if request.existingItems.isEmpty {
                    self?.apply(FoodLineResult(items: [FoodLoggingFallback.offlineItem(text: request.newText)]),
                                to: entryID)
                } else {
                    self?.apply(FoodLineResult(items: request.existingItems.map(FoodLoggingFallback.markFallback)),
                                to: entryID)
                }
            },
            shouldRetry: Self.isRetryableFillError
        )
    }

    /// `.missingKey` can't be fixed by another attempt, so fail fast to the Settings notice. Everything
    /// else (`.transient`, unexpected errors) earns the bounded backoff retries.
    nonisolated private static func isRetryableFillError(_ error: any Error) -> Bool {
        if case FoodLoggingError.missingKey = error { return false }
        return true
    }

    private static let missingKeyNotice = "Add your OpenRouter API key in Settings to estimate macros."

    private func apply(_ result: FoodLineResult, to entryID: String) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries[index].items = result.items
        entries[index].status = result.items.isEmpty ? .failed : .resolved
        persist()
    }

    private func markFailed(_ entryID: String, notice: String) {
        self.notice = notice
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries[index].status = .failed
        persist()
    }

    /// A fresh copy of a shortcut item with a new id so re-logs don't collide on identity.
    private func freshCopy(of item: LoggedFoodItem) -> LoggedFoodItem {
        var copy = item
        copy.id = UUID().uuidString
        return copy
    }
}

extension FoodLogStore {
    /// Current instant as an ISO 8601 string with fractional seconds (matches NutritionStore).
    nonisolated static func isoNow() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: .now)
    }

    /// A Date's local `YYYY-MM-DD` key (local-midnight boundary, matching the rest of the app).
    nonisolated static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The local day key for an entry's ISO timestamp (tolerates fractional-seconds presence/absence).
    nonisolated private static func dayKey(of entry: FoodJournalEntry) -> String {
        guard let date = parseISO(entry.loggedAt) else { return "" }
        return dayKey(date)
    }

    nonisolated(unsafe) private static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    nonisolated private static func parseISO(_ iso: String) -> Date? {
        if let date = isoWithFraction.date(from: iso) { return date }
        return isoPlain.date(from: iso)
    }

    /// The local `YYYY-MM-DD` key for an arbitrary ISO timestamp; lets the recent-history feed group
    /// lines by day without reaching into the private per-entry cache. Empty string if unparseable.
    nonisolated static func localDayKey(forISO iso: String) -> String {
        guard let date = parseISO(iso) else { return "" }
        return dayKey(date)
    }
}

#if DEBUG
extension FoodLogStore {
    /// DEBUG-only: seed pre-resolved lines onto today (timestamps spaced a few seconds apart so the
    /// newest-first sort is stable) for previews/screenshots. Never used in a real build.
    func seedToday(_ lines: [(text: String, items: [LoggedFoodItem], status: FoodEntryStatus)]) {
        let now = Date.now
        var seeded: [FoodJournalEntry] = []
        for (index, line) in lines.enumerated() {
            let stamped = Calendar.current.date(byAdding: .second, value: -index * 5, to: now) ?? now
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            seeded.append(FoodJournalEntry(
                foodText: line.text, items: line.items, status: line.status,
                loggedAt: formatter.string(from: stamped)
            ))
        }
        entries = seeded
        persist()
    }

    /// DEBUG-only: seed pre-resolved lines onto past days (each stamped `daysAgo` days before now, meals
    /// spaced 90 min apart within that evening) so the "Last 14 days" chart and averages read as a real
    /// logging habit rather than a single seeded day. Appends to whatever `seedToday` put on today, so
    /// call it after `seedToday`. Past-day lines never surface in the Today view (it filters to today)
    /// but flow through the journal mirror into the dashboard rollups. Never used in a real build.
    func seedHistory(_ history: [(daysAgo: Int, lines: [(text: String, items: [LoggedFoodItem], status: FoodEntryStatus)])]) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let calendar = Calendar.current
        let evening = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: Date.now) ?? Date.now
        var extra: [FoodJournalEntry] = []
        for day in history where day.daysAgo > 0 {
            guard let dayBase = calendar.date(byAdding: .day, value: -day.daysAgo, to: evening) else { continue }
            for (index, line) in day.lines.enumerated() {
                let stamped = calendar.date(byAdding: .minute, value: -index * 90, to: dayBase) ?? dayBase
                extra.append(FoodJournalEntry(
                    foodText: line.text, items: line.items, status: line.status,
                    loggedAt: formatter.string(from: stamped)
                ))
            }
        }
        entries.append(contentsOf: extra)
        persist()
    }
}
#endif
