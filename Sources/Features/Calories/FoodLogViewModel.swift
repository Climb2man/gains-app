import Foundation
import Observation

@MainActor
@Observable
final class FoodLogViewModel {
    /// The local day key currently shown (swipe to adjacent days).
    var selectedDay: String
    /// The composer's current text.
    var composerText: String = ""
    /// Which logged line has its assumptions/details expanded (tap-to-reveal), if any.
    var expandedEntryID: String?
    /// The line being saved as a shortcut (drives the SaveFoodSheet), if any.
    var savingEntry: FoodJournalEntry?
    /// The line being edited (drives the EditFoodSheet), if any.
    var editingEntry: FoodJournalEntry?
    /// Whether the barcode scanner sheet is presented.
    var isScanningBarcode = false

    private let foodLog: FoodLogStore
    private let savedFoods: SavedFoodsStore
    private let settings: FoodLogSettingsStore
    private let nutrition: NutritionStore

    init(
        foodLog: FoodLogStore,
        savedFoods: SavedFoodsStore,
        settings: FoodLogSettingsStore,
        nutrition: NutritionStore,
        day: String? = nil
    ) {
        self.foodLog = foodLog
        self.savedFoods = savedFoods
        self.settings = settings
        self.nutrition = nutrition
        self.selectedDay = day ?? FoodLogStore.dayKey(.now)
    }

    var todayKey: String { FoodLogStore.dayKey(.now) }
    var isToday: Bool { selectedDay == todayKey }
    var dayTitle: String { CaloriesSupport.dayTitle(selectedDay) }
    var bias: CalorieBias { settings.bias }
    var micronutrients: MicronutrientToggles { settings.micronutrients }
    var goals: Goals { nutrition.goals }

    var entries: [FoodJournalEntry] { foodLog.entries(on: selectedDay) }
    var totals: FoodDayTotals { foodLog.totals(on: selectedDay) }

    /// The quick-add shortcuts (most-used first, capped for the chip row).
    var shortcuts: [FoodShortcut] { Array(savedFoods.shortcuts.prefix(8)) }
    /// Recently-used meals derived from the journal, for one-tap re-log.
    var recents: [RecentMeal] { Array(nutrition.recentMeals.prefix(6)) }

    /// Foods the user has eaten before, for the "close your rings" suggestions.
    ///
    /// Saved meals come first and win ties on de-duplication: a saved meal is something the user
    /// deliberately kept, where a recent is merely something that happened. De-duped on the same
    /// normalised name the rest of the app uses, so "Greek yoghurt" and "greek yogurt " collapse.
    var suggestionCandidates: [MacroGapRecommender.Candidate] {
        var seen = Set<String>()
        var out: [MacroGapRecommender.Candidate] = []

        for meal in nutrition.savedMeals {
            let key = NutritionStore.normalizeName(meal.name)
            guard seen.insert(key).inserted else { continue }
            out.append(.init(id: "saved:\(meal.id)", name: meal.name, calories: meal.calories,
                             proteinG: meal.proteinG, carbsG: meal.carbsG, fatG: meal.fatG))
        }
        for recent in nutrition.recentMeals {
            let key = NutritionStore.normalizeName(recent.name)
            guard seen.insert(key).inserted else { continue }
            out.append(.init(id: "recent:\(key)", name: recent.name, calories: recent.calories,
                             proteinG: recent.proteinG, carbsG: recent.carbsG, fatG: recent.fatG))
        }
        return out
    }

    /// Log a suggestion into today. Routes through `logRecent` so it takes the same path as any
    /// other re-log — including the lookup that recovers the original resolved item.
    func logSuggestion(_ candidate: MacroGapRecommender.Candidate) {
        logRecent(RecentMeal(
            name: candidate.name,
            calories: candidate.calories,
            proteinG: candidate.proteinG,
            carbsG: candidate.carbsG,
            fatG: candidate.fatG
        ))
    }
    /// Nickname autocomplete matches for the current composer text.
    var suggestions: [FoodShortcut] { savedFoods.autocomplete(composerText) }

    /// The composer chip row, filtered by the composer text. Empty field shows the full quick-add set;
    /// typing narrows to saved meals whose names contain the query. Capped for the row.
    var filteredShortcuts: [FoodShortcut] {
        let query = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = savedFoods.shortcuts
        let matched = query.isEmpty ? base : base.filter { $0.nickname.localizedStandardContains(query) }
        return Array(matched.prefix(8))
    }

    /// Recents filtered by the composer text and deduped against saved meals so a meal never appears in
    /// both rows. Dedupes against unsorted `shortcutsRaw` (a Set) rather than `filteredShortcuts` to
    /// avoid re-sorting the saved meals on every keystroke. Empty field shows the top recents.
    var filteredRecents: [RecentMeal] {
        let query = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = nutrition.recentMeals
        let matched = query.isEmpty ? base : base.filter { $0.name.localizedStandardContains(query) }
        let savedNames = Set(savedFoods.shortcutsRaw.map { SavedFoodsStore.normalize($0.nickname) })
        return Array(matched.filter { !savedNames.contains(SavedFoodsStore.normalize($0.name)) }.prefix(6))
    }

    /// The previous and next day keys so the day pager can prefetch.
    var adjacentDays: (previous: String, next: String) {
        (offsetDay(-1), offsetDay(1))
    }

    func goToPreviousDay() { selectedDay = offsetDay(-1) }
    func goToNextDay() { if !isToday { selectedDay = offsetDay(1) } }
    func goToToday() { selectedDay = todayKey }

    private func offsetDay(_ delta: Int) -> String {
        let base = CaloriesSupport.keyToDate(selectedDay)
        guard let shifted = Calendar.current.date(byAdding: .day, value: delta, to: base) else {
            return selectedDay
        }
        return FoodLogStore.dayKey(shifted)
    }

    /// Submit the composer text as a new optimistic line. Clears the field.
    func submitComposer() {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        goToToday()
        foodLog.logLine(text, bias: bias, micronutrients: micronutrients)
        composerText = ""
    }

    /// One-tap re-log a saved shortcut (zero AI). Bumps its use count for ordering.
    func logShortcut(_ shortcut: FoodShortcut) {
        goToToday()
        foodLog.logShortcut(shortcut)
        savedFoods.bumpUse(id: shortcut.id)
        composerText = ""
    }

    /// One-tap re-log a recent meal (zero AI). Prefers the full original item from the journal (keeping
    /// its provenance, citations, confidence, assumptions), falling back to a bare item from the
    /// recent's summary macros when no source line is found. Recents are keyed on item name.
    func logRecent(_ recent: RecentMeal) {
        goToToday()
        let target = NutritionStore.normalizeName(recent.name)
        let sourceItem = foodLog.recentLines()
            .flatMap(\.items)
            .first { NutritionStore.normalizeName($0.name) == target }
        let item = sourceItem ?? LoggedFoodItem(
            name: recent.name, calories: recent.calories,
            proteinG: recent.proteinG, carbsG: recent.carbsG, fatG: recent.fatG
        )
        foodLog.logShortcut(FoodShortcut(
            nickname: recent.name,
            items: [item],
            source: "recent",
            createdAt: FoodLogStore.isoNow(),
            updatedAt: FoodLogStore.isoNow()
        ))
        composerText = ""
    }

    /// Toggle the expanded assumptions/details for a line (tap-to-reveal).
    func toggleDetails(_ entry: FoodJournalEntry) {
        expandedEntryID = expandedEntryID == entry.id ? nil : entry.id
    }

    /// Re-type an existing line (cheap portion path when applicable).
    func retype(_ entry: FoodJournalEntry, to newText: String) {
        foodLog.editLine(id: entry.id, newText: newText, bias: bias, micronutrients: micronutrients)
    }

    /// Persist a hand-corrected item (one-tap correction, no AI).
    func correctItem(_ entry: FoodJournalEntry, item: LoggedFoodItem) {
        foodLog.updateItem(entryID: entry.id, item: item)
    }

    /// Retry a failed line (e.g. after adding a key).
    func retry(_ entry: FoodJournalEntry) {
        foodLog.retry(id: entry.id, bias: bias, micronutrients: micronutrients)
    }

    func delete(_ entry: FoodJournalEntry) {
        foodLog.removeLine(id: entry.id)
    }

    func beginSave(_ entry: FoodJournalEntry) { savingEntry = entry }
    func beginEdit(_ entry: FoodJournalEntry) { editingEntry = entry }

    /// Open the barcode scanner sheet.
    func beginScanBarcode() { isScanningBarcode = true }

    /// Log an item resolved from a barcode scan (Open Food Facts) or its label-photo fallback. Lands on
    /// today as an already-resolved line, no further AI; the scan produced the macros. Stays editable.
    func logScannedItem(_ item: LoggedFoodItem) {
        goToToday()
        foodLog.logCapturedLine(text: item.name, items: [item])
    }
}
