import Foundation
import Observation

@MainActor
@Observable
final class WorkoutStore {
    private static let entriesKey = "@gains/workoutlog/entries"
    private static let shortcutsKey = "@gains/workoutlog/shortcuts"

    /// All logged sessions across all days (unsorted, as written). Day views filter + sort.
    private(set) var entries: [WorkoutEntry] = []
    /// The saved/recent shortcuts for one-tap re-log (most-used first via `shortcuts`).
    private(set) var shortcutsRaw: [WorkoutShortcut] = []

    private let store: any KeyValueStore
    private let service: any WorkoutParsing

    /// A non-credential, user-facing notice (e.g. "add your key in Settings"). Never holds a key.
    var notice: String?

    init(service: any WorkoutParsing, store: any KeyValueStore = EncryptedFileStore.shared) {
        self.service = service
        self.store = store
        load()
    }

    private func load() {
        if let storedEntries = store.value([WorkoutEntry].self, forKey: Self.entriesKey) {
            entries = storedEntries
        }
        if let storedShortcuts = store.value([WorkoutShortcut].self, forKey: Self.shortcutsKey) {
            shortcutsRaw = storedShortcuts
        }
    }

    private func persistEntries() {
        store.setValue(entries, forKey: Self.entriesKey)
    }

    private func persistShortcuts() {
        store.setValue(shortcutsRaw, forKey: Self.shortcutsKey)
    }

    /// The sessions logged on `dayKey`'s local day, newest first.
    func entries(on dayKey: String) -> [WorkoutEntry] {
        entries
            .filter { Self.dayKey(of: $0) == dayKey }
            .sorted { $0.date > $1.date }
    }

    /// Whether ANY session exists on a day. Lets a date strip mark trained days.
    func hasEntries(on dayKey: String) -> Bool {
        entries.contains { Self.dayKey(of: $0) == dayKey }
    }

    /// Log a new natural-language workout. Inserts an optimistic `.pending` row so the UI never waits,
    /// then parses via the service and flips the row to `.resolved`/`.failed`. Returns the session id.
    @discardableResult
    func logWorkout(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = WorkoutEntry(date: Self.isoNow(), rawText: trimmed, status: .pending, source: .typed)
        entries.append(entry)
        persistEntries()

        Task { await resolve(entryID: entry.id, text: trimmed) }
        return entry.id
    }

    /// Re-log a saved shortcut to today in one tap: inserts a `.resolved` session from the saved
    /// snapshot with no AI call, offline. Bumps its use count for ordering. Returns the new session id.
    @discardableResult
    func logShortcut(_ shortcut: WorkoutShortcut) -> String {
        let entry = WorkoutEntry(
            date: Self.isoNow(),
            title: shortcut.nickname,
            exercises: shortcut.exercises.map(freshCopy(of:)),
            rawText: shortcut.nickname,
            status: .resolved,
            source: .shortcut
        )
        entries.append(entry)
        persistEntries()
        bumpUse(id: shortcut.id)
        return entry.id
    }

    /// Edit an existing session by re-typing it in plain text. Updates the raw text, flips the row back
    /// to `.pending`, and re-parses.
    func editWorkout(id: String, newText: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        entries[index].rawText = trimmed
        entries[index].status = .pending
        persistEntries()
        Task { await resolve(entryID: id, text: trimmed) }
    }

    /// Retry a `.failed` session (e.g. after the user added their key). Re-runs the original text.
    func retry(id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let text = entries[index].rawText
        entries[index].status = .pending
        persistEntries()
        Task { await resolve(entryID: id, text: text) }
    }

    /// Delete a logged session (swipe-to-delete in the notes list). A plain removal; no streak to recompute.
    func removeWorkout(id: String) {
        entries.removeAll { $0.id == id }
        persistEntries()
    }

    /// Shortcuts ordered for the quick-add row: most-used first, then most-recent.
    var shortcuts: [WorkoutShortcut] {
        shortcutsRaw.sorted { a, b in
            if a.useCount != b.useCount { return a.useCount > b.useCount }
            return a.updatedAt > b.updatedAt
        }
    }

    /// Save (or update) a shortcut from a resolved session. If the nickname already exists (normalized),
    /// its snapshot is refreshed in place (no duplicate) and `updatedAt` bumped. Returns the shortcut.
    @discardableResult
    func saveShortcut(nickname: String, exercises: [WorkoutExercise]) -> WorkoutShortcut {
        let now = Self.isoNow()
        let norm = Self.normalize(nickname)
        let snapshot = exercises.map(freshCopy(of:))

        if let existing = shortcutsRaw.first(where: { Self.normalize($0.nickname) == norm }) {
            var updated = existing
            updated.nickname = nickname
            updated.exercises = snapshot
            updated.updatedAt = now
            shortcutsRaw = shortcutsRaw.map { $0.id == existing.id ? updated : $0 }
            persistShortcuts()
            return updated
        }

        let shortcut = WorkoutShortcut(
            nickname: nickname, exercises: snapshot, useCount: 0, createdAt: now, updatedAt: now
        )
        shortcutsRaw.append(shortcut)
        persistShortcuts()
        return shortcut
    }

    /// Bump usage after a shortcut is re-logged (orders the quick-add row). No-op if absent.
    func bumpUse(id: String) {
        shortcutsRaw = shortcutsRaw.map { shortcut in
            guard shortcut.id == id else { return shortcut }
            var bumped = shortcut
            bumped.useCount += 1
            bumped.updatedAt = Self.isoNow()
            return bumped
        }
        persistShortcuts()
    }

    /// Delete a saved shortcut (past sessions untouched, history stays honest).
    func removeShortcut(id: String) {
        shortcutsRaw.removeAll { $0.id == id }
        persistShortcuts()
    }

    private func resolve(entryID: String, text: String) async {
        do {
            let result = try await service.parse(text)
            apply(result, to: entryID)
        } catch AIProviderError.missingKey {
            markFailed(entryID, notice: "Add your OpenRouter API key in Settings to parse workouts.")
        } catch {
            markFailed(entryID, notice: "Couldn't read that workout. Tap it to edit, or try again.")
        }
    }

    private func apply(_ result: WorkoutParseResult, to entryID: String) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries[index].exercises = result.exercises
        if entries[index].title == nil { entries[index].title = result.title }
        entries[index].lowConfidence = result.lowConfidence
        entries[index].status = result.exercises.isEmpty ? .failed : .resolved
        persistEntries()
    }

    private func markFailed(_ entryID: String, notice: String) {
        self.notice = notice
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries[index].status = .failed
        persistEntries()
    }

    /// A fresh copy of an exercise and its sets with new ids so re-logs don't collide on identity.
    private func freshCopy(of exercise: WorkoutExercise) -> WorkoutExercise {
        var copy = exercise
        copy.id = UUID().uuidString
        copy.sets = copy.sets.map { set in
            var setCopy = set
            setCopy.id = UUID().uuidString
            return setCopy
        }
        return copy
    }
}

extension WorkoutStore {
    /// Current instant as an ISO 8601 string with fractional seconds (matches FoodLogStore).
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

    /// The local day key for a session's ISO timestamp.
    nonisolated private static func dayKey(of entry: WorkoutEntry) -> String {
        guard let date = parseISO(entry.date) else { return "" }
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

    /// Normalize a nickname for dedupe/match: trimmed, lowercased, inner whitespace collapsed.
    nonisolated static func normalize(_ name: String) -> String {
        let lowered = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowered.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

#if DEBUG
extension WorkoutStore {
    /// DEBUG-only: seed pre-parsed sessions onto today for previews/screenshots, spacing timestamps a
    /// few seconds apart so the newest-first sort is stable. Never used in a real build.
    func seedToday(_ sessions: [(title: String?, rawText: String, exercises: [WorkoutExercise], status: WorkoutEntryStatus, lowConfidence: Bool)]) {
        let now = Date.now
        var seeded: [WorkoutEntry] = []
        for (index, session) in sessions.enumerated() {
            let stamped = Calendar.current.date(byAdding: .second, value: -index * 5, to: now) ?? now
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            seeded.append(WorkoutEntry(
                date: formatter.string(from: stamped),
                title: session.title,
                exercises: session.exercises,
                rawText: session.rawText,
                status: session.status,
                source: .typed,
                lowConfidence: session.lowConfidence
            ))
        }
        entries = seeded
        persistEntries()
    }

    /// DEBUG-only: seed saved shortcuts directly for previews/screenshots.
    func seedShortcuts(_ shortcuts: [WorkoutShortcut]) {
        shortcutsRaw = shortcuts
        persistShortcuts()
    }
}
#endif
