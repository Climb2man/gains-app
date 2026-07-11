import Foundation
import Observation

@MainActor
@Observable
final class WorkoutLogViewModel {
    /// The local day key currently shown.
    var selectedDay: String
    /// The composer's current text.
    var composerText: String = ""
    /// Which logged session has its exercise detail expanded, if any.
    var expandedEntryID: String?
    /// The session being saved as a shortcut (drives the save alert), if any.
    var savingEntry: WorkoutEntry?
    /// The session being edited (drives the edit alert), if any.
    var editingEntry: WorkoutEntry?

    private let store: WorkoutStore

    init(store: WorkoutStore, day: String? = nil) {
        self.store = store
        self.selectedDay = day ?? WorkoutStore.dayKey(.now)
    }

    var todayKey: String { WorkoutStore.dayKey(.now) }
    var isToday: Bool { selectedDay == todayKey }
    var dayTitle: String { CaloriesSupport.dayTitle(selectedDay) }

    var entries: [WorkoutEntry] { store.entries(on: selectedDay) }
    /// The quick-add shortcuts (most-used first, capped for the chip row).
    var shortcuts: [WorkoutShortcut] { Array(store.shortcuts.prefix(8)) }

    func goToPreviousDay() { selectedDay = offsetDay(-1) }
    func goToNextDay() { if !isToday { selectedDay = offsetDay(1) } }
    func goToToday() { selectedDay = todayKey }

    private func offsetDay(_ delta: Int) -> String {
        let base = CaloriesSupport.keyToDate(selectedDay)
        guard let shifted = Calendar.current.date(byAdding: .day, value: delta, to: base) else {
            return selectedDay
        }
        return WorkoutStore.dayKey(shifted)
    }

    /// Submit the composer text as a new optimistic session, clearing the field. Logs always land on
    /// today (a real timestamp), so jump there to keep the new session visible.
    func submitComposer() {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        goToToday()
        store.logWorkout(text)
        composerText = ""
    }

    /// One-tap re-log a saved shortcut (zero AI). The store bumps its use count for ordering.
    func logShortcut(_ shortcut: WorkoutShortcut) {
        goToToday()
        store.logShortcut(shortcut)
        composerText = ""
    }

    /// Toggle the expanded exercise detail for a session.
    func toggleDetails(_ entry: WorkoutEntry) {
        expandedEntryID = expandedEntryID == entry.id ? nil : entry.id
    }

    /// Re-type an existing session (re-parses).
    func retype(_ entry: WorkoutEntry, to newText: String) {
        store.editWorkout(id: entry.id, newText: newText)
    }

    /// Retry a failed session (e.g. after adding a key).
    func retry(_ entry: WorkoutEntry) {
        store.retry(id: entry.id)
    }

    func delete(_ entry: WorkoutEntry) {
        store.removeWorkout(id: entry.id)
    }

    func beginSave(_ entry: WorkoutEntry) { savingEntry = entry }
    func beginEdit(_ entry: WorkoutEntry) { editingEntry = entry }

    /// Save a resolved session as a nicknamed shortcut for one-tap re-log.
    func saveShortcut(_ entry: WorkoutEntry, nickname: String) {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !entry.exercises.isEmpty else { return }
        store.saveShortcut(nickname: trimmed, exercises: entry.exercises)
    }
}
