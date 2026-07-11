import Foundation
import Observation

@MainActor
@Observable
final class JournalStore {
    private static let notesKey = "@gains/journal/notes"

    /// All notes across all days (unsorted, as written). Day views filter + sort.
    private(set) var notes: [JournalNote] = []

    private let store: any KeyValueStore

    init(store: any KeyValueStore = EncryptedFileStore.shared) {
        self.store = store
        if let stored = store.value([JournalNote].self, forKey: Self.notesKey) {
            notes = stored
        }
    }

    private func persist() {
        store.setValue(notes, forKey: Self.notesKey)
    }

    /// The notes written on `dayKey`'s local day, newest first.
    func notes(on dayKey: String) -> [JournalNote] {
        notes
            .filter { Self.dayKey(of: $0) == dayKey }
            .sorted { $0.date > $1.date }
    }

    /// Write a new note (timestamped now). No-op on empty/whitespace text.
    @discardableResult
    func addNote(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let note = JournalNote(date: Self.isoNow(), text: trimmed)
        notes.append(note)
        persist()
        return note.id
    }

    /// Replace a note's text in place (timestamp and day untouched, so the note stays where it was
    /// written). Deletes nothing: an edit to empty text is ignored, delete is explicit.
    func editNote(id: String, newText: String) {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].text = trimmed
        persist()
    }

    /// Delete a note (swipe-to-delete in the list).
    func removeNote(id: String) {
        notes.removeAll { $0.id == id }
        persist()
    }
}

extension JournalStore {
    /// Current instant as an ISO 8601 string with fractional seconds (matches FoodLogStore).
    nonisolated static func isoNow() -> String {
        isoWithFraction.string(from: .now)
    }

    /// A Date's local `YYYY-MM-DD` key (local-midnight boundary, matching the rest of the app).
    nonisolated static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The local day key for a note's ISO timestamp.
    nonisolated private static func dayKey(of note: JournalNote) -> String {
        guard let date = parseISO(note.date) else { return "" }
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

    /// Parse a stored ISO timestamp (with or without fractional seconds). The row uses this to show
    /// the note's local time-of-day.
    nonisolated static func parseISO(_ iso: String) -> Date? {
        if let date = isoWithFraction.date(from: iso) { return date }
        return isoPlain.date(from: iso)
    }
}

#if DEBUG
extension JournalStore {
    /// DEBUG-only: seed notes onto today (timestamps spaced so the newest-first sort is stable) for
    /// previews/screenshots. Never used in a real build.
    func seedToday(_ texts: [String]) {
        let now = Date.now
        notes = texts.enumerated().map { index, text in
            let stamped = Calendar.current.date(byAdding: .minute, value: -index * 90, to: now) ?? now
            return JournalNote(date: Self.isoWithFraction.string(from: stamped), text: text)
        }
        persist()
    }
}
#endif
