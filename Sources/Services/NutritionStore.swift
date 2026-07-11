import Foundation
import Observation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// The fields a caller supplies to log an entry; `id` + `loggedAt` are generated.
struct FoodInput: Sendable {
    var name: String
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var source: FoodSource
}

/// The fields a caller supplies when saving a reusable meal.
struct SavedMealInput: Sendable {
    var name: String
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
}

/// One day's roll-up against the user's goals.
///
/// Hit rules: protein is a floor (meet-or-exceed); calories a ceiling (at-or-under, deficit-friendly).
/// `hit` = both met. A day with zero logged calories isn't a calorie hit, so streaks/hit-rates only
/// reward logged days.
struct DayHistory: Equatable, Sendable {
    var date: String
    var totals: DailyTotals
    var loggedAnything: Bool
    var caloriesHit: Bool
    var proteinHit: Bool
    var hit: Bool
}

/// `hitRate(n)` result: how many of the last n days hit both goals.
struct HitRate: Equatable, Sendable {
    var hits: Int
    var total: Int
    /// 0…1 (0 when `total` is 0).
    var rate: Double
}

@MainActor
@Observable
final class NutritionStore {
    private static let entriesKey = "@gains/nutrition/entries"
    private static let goalsKey = "@gains/nutrition/goals"
    private static let savedKey = "@gains/nutrition/saved"
    private static let timelineKey = "@gains/nutrition/goals-timeline"
    private static let recipeKey = "@gains/nutrition/goal-recipe"
    private static let autoAdjustKey = "@gains/nutrition/goal-auto-adjust"

    /// All logged entries (unsorted, as written). Drives the today ledger + history.
    /// Mirrored from the FoodLogStore journal (wired in AppModel; the journal is the single source of
    /// truth for logged food). Direct writes (`addEntry`/`removeEntry`) are DEBUG-sample/test paths;
    /// the next journal mutation overwrites them via `mirrorJournal(_:)`.
    private(set) var entries: [FoodEntry] = []
    /// The user's calorie/protein/fat/carb targets. Defaults to `Goals.default` until set.
    private(set) var goals: Goals = .default
    /// Dated goal versions, oldest first: every per-day hit/miss is judged against the goals active
    /// that day, so a goal change (manual or auto-adjust) never rewrites streak history.
    private(set) var goalsTimeline: [GoalsVersion] = []
    /// The saved calculator inputs that let goals re-derive from the current weight (nil until the
    /// user applies the calculator in GoalsView; auto-adjust is impossible without one).
    private(set) var goalRecipe: GoalRecipe?
    /// User-visible switch (GoalsView): when on (and a recipe exists), the calorie/macro goals
    /// recalculate from the current weight on every weight change and day rollover.
    private(set) var autoAdjustsGoals = false
    /// Explicitly-saved reusable meals (favorites). Read via `savedMeals` (sorted).
    private(set) var savedMealsRaw: [SavedMeal] = []

    private let store: any KeyValueStore

    /// Monotonic per-launch counter so two entries created in the same millisecond get distinct ids
    /// without randomness (`<epochMs>-<counter>`).
    private var idCounter = 0

    /// The last `WidgetSnapshot` written to the App Group (seeded from disk; this store is the only
    /// writer). Lets `syncWidgetSnapshot()` skip the write + timeline reload when nothing changed, so
    /// a launch with no new data never wakes the widget extension to rebuild an identical timeline.
    private var lastWidgetSnapshot: WidgetSnapshot? = WidgetSharedStore.read()

    init(store: any KeyValueStore = EncryptedFileStore.shared) {
        self.store = store
        load()
        syncWidgetSnapshot()
    }

    /// Load entries/goals/saved from disk. Defensive: a missing or undecodable blob leaves the default
    /// in place (safe-parse with a silent skip on each key).
    private func load() {
        if let stored = store.value([FoodEntry].self, forKey: Self.entriesKey) { entries = stored }
        if let stored = store.value(Goals.self, forKey: Self.goalsKey) { goals = stored }
        if let stored = store.value([SavedMeal].self, forKey: Self.savedKey) { savedMealsRaw = stored }
        if let stored = store.value([GoalsVersion].self, forKey: Self.timelineKey) { goalsTimeline = stored }
        if goalsTimeline.isEmpty { goalsTimeline = [GoalsVersion(effectiveFrom: "", goals: goals)] }
        if let stored = store.value(GoalRecipe.self, forKey: Self.recipeKey) { goalRecipe = stored }
        if let stored = store.value(Bool.self, forKey: Self.autoAdjustKey) { autoAdjustsGoals = stored }
    }

    private func makeId() -> String {
        idCounter += 1
        return "\(Int(Date().timeIntervalSince1970 * 1000))-\(idCounter)"
    }

    /// Log a new entry (generates `id` + `loggedAt = now`).
    func addEntry(_ input: FoodInput) {
        let entry = FoodEntry(
            id: makeId(),
            name: input.name,
            calories: input.calories,
            proteinG: input.proteinG,
            carbsG: input.carbsG,
            fatG: input.fatG,
            source: input.source,
            loggedAt: Self.isoNow()
        )
        entries.append(entry)
        store.setValue(entries, forKey: Self.entriesKey)
        syncWidgetSnapshot()
    }

    /// Remove an entry by id (no-op if absent).
    func removeEntry(id: String) {
        entries.removeAll { $0.id == id }
        store.setValue(entries, forKey: Self.entriesKey)
        syncWidgetSnapshot()
    }

    /// Replace the goals and persist. The change takes effect today (a same-day re-save replaces
    /// today's version), so past days keep being judged against the goals that were active then.
    func setGoals(_ next: Goals) {
        goals = next
        store.setValue(next, forKey: Self.goalsKey)
        let today = Self.dayKey(Date())
        goalsTimeline.removeAll { $0.effectiveFrom == today }
        goalsTimeline.append(GoalsVersion(effectiveFrom: today, goals: next))
        goalsTimeline.sort { $0.effectiveFrom < $1.effectiveFrom }
        store.setValue(goalsTimeline, forKey: Self.timelineKey)
        syncWidgetSnapshot()
    }

    /// The goals active on a local day: the latest version effective on-or-before it (the ""
    /// legacy seed covers every day predating goal versioning).
    func goals(on dayKey: String) -> Goals {
        goalsTimeline.last(where: { $0.effectiveFrom <= dayKey })?.goals ?? goals
    }

    /// Save (or clear) the auto-adjust recipe + switch (GoalsView). A nil recipe forces the switch
    /// off: auto-adjust without calculator inputs is meaningless.
    func setGoalRecipe(_ recipe: GoalRecipe?, autoAdjust: Bool) {
        goalRecipe = recipe
        autoAdjustsGoals = recipe != nil && autoAdjust
        if let recipe {
            store.setValue(recipe, forKey: Self.recipeKey)
        } else {
            store.removeValue(forKey: Self.recipeKey)
        }
        store.setValue(autoAdjustsGoals, forKey: Self.autoAdjustKey)
    }

    /// Auto-adjust: re-derive the calorie/macro goals from the current weight through the saved recipe.
    /// Runs on profile changes (weight edit, Apple Health import) and day rollover; a no-op unless the
    /// switch is on, a recipe exists, and the derived numbers changed. The steps goal is preserved (the
    /// calculator has no step model). Streak history stays intact: `setGoals` versions the change from today.
    func autoAdjustGoals(profile: Profile) {
        guard autoAdjustsGoals, let recipe = goalRecipe,
              let activity = GoalCalculator.ActivityLevel(rawValue: recipe.activity),
              let direction = GoalCalculator.GoalDirection(rawValue: recipe.direction) else { return }
        let result = GoalCalculator.estimate(profile: profile, activity: activity, goal: direction)
        let next = Goals(
            calorieGoal: Double(result.calorieGoal), proteinGoal: Double(result.proteinGoal),
            fatGoal: Double(result.fatGoal), carbGoal: Double(result.carbGoal),
            stepsGoal: goals.stepsGoal
        )
        guard next != goals else { return }
        setGoals(next)
    }

    /// Persist the next saved-meals list and update state in one place.
    private func persistSaved(_ next: [SavedMeal]) {
        savedMealsRaw = next
        store.setValue(next, forKey: Self.savedKey)
    }

    /// Save a meal as a reusable favorite. If a meal with the same normalized name exists, update its
    /// macros in place (no duplicate). Returns the saved meal.
    @discardableResult
    func saveMeal(_ input: SavedMealInput) -> SavedMeal {
        let now = Self.isoNow()
        let norm = Self.normalizeName(input.name)
        if let existing = savedMealsRaw.first(where: { Self.normalizeName($0.name) == norm }) {
            let meal = SavedMeal(
                id: existing.id,
                name: input.name,
                calories: input.calories,
                proteinG: input.proteinG,
                carbsG: input.carbsG,
                fatG: input.fatG,
                createdAt: existing.createdAt,
                lastUsedAt: now,
                useCount: existing.useCount
            )
            persistSaved(savedMealsRaw.map { $0.id == existing.id ? meal : $0 })
            return meal
        }
        let meal = SavedMeal(
            id: makeId(),
            name: input.name,
            calories: input.calories,
            proteinG: input.proteinG,
            carbsG: input.carbsG,
            fatG: input.fatG,
            createdAt: now,
            lastUsedAt: now,
            useCount: 0
        )
        persistSaved(savedMealsRaw + [meal])
        return meal
    }

    /// Delete a saved meal (past log entries untouched, history stays honest).
    func removeSavedMeal(id: String) {
        persistSaved(savedMealsRaw.filter { $0.id != id })
    }

    /// Bump a saved meal's usage after it's re-logged (increment useCount + refresh lastUsedAt). No-op
    /// if the id isn't found.
    func bumpUse(id: String) {
        let now = Self.isoNow()
        persistSaved(savedMealsRaw.map { meal in
            guard meal.id == id else { return meal }
            var bumped = meal
            bumped.useCount += 1
            bumped.lastUsedAt = now
            return bumped
        })
    }

    /// Re-log a saved meal to today in one tap: create a today entry from its confirmed macros
    /// (source `.saved`, no AI call) and bump its usage.
    func logSavedMeal(_ meal: SavedMeal) {
        addEntry(FoodInput(
            name: meal.name,
            calories: meal.calories,
            proteinG: meal.proteinG,
            carbsG: meal.carbsG,
            fatG: meal.fatG,
            source: .saved
        ))
        bumpUse(id: meal.id)
    }

    /// Saved meals sorted for the "Saved & recent" list: most-used first, then most-recent.
    var savedMeals: [SavedMeal] {
        savedMealsRaw.sorted { a, b in
            if a.useCount != b.useCount { return a.useCount > b.useCount }
            return a.lastUsedAt > b.lastUsedAt
        }
    }

    /// Recents derived from the entry history (dedupe by normalized name, newest macros, exclude
    /// already-saved names, sort by frequency then recency).
    var recentMeals: [RecentMeal] {
        Self.deriveRecents(entries: entries, savedMeals: savedMealsRaw)
    }

    /// Today's summed totals.
    var todayTotals: DailyTotals {
        Self.sumForDay(entries, key: Self.dayKey(Date()))
    }

    /// Totals for any local day (the date-strip "browse past days" feature).
    func totalsForDay(_ date: Date) -> DailyTotals {
        Self.sumForDay(entries, key: Self.dayKey(date))
    }

    /// The last `rangeDays` days, oldest first through today, each with totals + hit/miss vs the goals
    /// active on that day.
    func dailyHistory(_ rangeDays: Int) -> [DayHistory] {
        Self.recentDayKeys(rangeDays).map { Self.dayHistory(entries, key: $0, goals: goals(on: $0)) }
    }

    /// Current streak: consecutive goal-hitting days back from today (an un-hit today doesn't break a
    /// prior run).
    var currentStreak: Int { streakSummary().current }

    /// Longest run of fully-hit days anywhere in history.
    var longestStreak: Int { streakSummary().longest }

    /// Timeline-aware streaks: each day is judged against its own day's goals, so a recalculated
    /// goal never rewrites past hit/miss days.
    func streakSummary() -> (current: Int, longest: Int) {
        Self.streakSummary(entries: entries) { [self] key in goals(on: key) }
    }

    /// How many of the last `rangeDays` days hit both goals (each vs its own day's goals).
    func hitRate(_ rangeDays: Int) -> HitRate {
        let days = Self.recentDayKeys(rangeDays).map { Self.dayHistory(entries, key: $0, goals: goals(on: $0)) }
        let hits = days.filter { $0.hit }.count
        let total = days.count
        return HitRate(hits: hits, total: total, rate: total > 0 ? Double(hits) / Double(total) : 0)
    }
}

extension NutritionStore {
    /// Replace the entry rollup with the journal-derived rows, persist, and refresh the widget
    /// snapshot. No-op when the derived rows are unchanged.
    func mirrorJournal(_ journal: [FoodJournalEntry]) {
        let mapped = Self.entriesFromJournal(journal)
        guard mapped != entries else { return }
        entries = mapped
        store.setValue(entries, forKey: Self.entriesKey)
        syncWidgetSnapshot()
    }

    /// Map journal lines to flat rollup rows: one `FoodEntry` per non-water item, stamped with its
    /// line's timestamp. Matches `FoodLogStore.totals(on:)` exactly: items count regardless of the
    /// line's status (a line mid-re-edit keeps its last numbers), water never reaches calories.
    /// A `.pending`/`.failed` line with no items contributes nothing.
    static func entriesFromJournal(_ journal: [FoodJournalEntry]) -> [FoodEntry] {
        journal.flatMap { line in
            line.items.compactMap { item -> FoodEntry? in
                guard !item.isWaterEntry else { return nil }
                return FoodEntry(
                    id: "\(line.id)#\(item.id)",
                    name: item.name,
                    calories: item.calories,
                    proteinG: item.proteinG,
                    carbsG: item.carbsG,
                    fatG: item.fatG,
                    source: .aiEstimated,
                    loggedAt: line.loggedAt
                )
            }
        }
    }
}

extension NutritionStore {
    /// Write today's calories-vs-goal into the shared App Group store and reload the widget timelines.
    /// A no-op when the snapshot is unchanged since the last write, so it's idempotent and safe to call
    /// on every mutation and on launch. Only calories drive the widget; recovery/steps stay `nil` here
    /// (the Whoop store owns those and can extend the snapshot later).
    func syncWidgetSnapshot() {
        let today = Self.dayKey(Date())
        let totals = todayTotals
        let snapshot = WidgetSnapshot(
            date: today,
            caloriesConsumed: Int(totals.calories.rounded()),
            calorieGoal: Int(goals.calorieGoal.rounded())
        )
        guard snapshot != lastWidgetSnapshot else { return }
        lastWidgetSnapshot = snapshot
        WidgetSharedStore.write(snapshot)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

extension NutritionStore {
    /// Current instant as an ISO 8601 string with fractional seconds.
    static func isoNow() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    /// Format a Date as its local `YYYY-MM-DD` key (no UTC day-shifting). Every per-day grouping uses a
    /// local-midnight boundary, so "today" never drifts across a UTC offset.
    static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let y = c.year ?? 0, m = c.month ?? 0, d = c.day ?? 0
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// The local day key for an ISO timestamp, or `nil` when unparseable.
    static func entryDayKey(_ iso: String) -> String? {
        guard let date = parseISO(iso) else { return nil }
        return dayKey(date)
    }

    /// Parse an ISO 8601 timestamp, tolerating presence/absence of fractional seconds (the offline
    /// fallback and the model may differ). Returns `nil` on failure, never a fabricated date.
    private static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parseISO(_ iso: String) -> Date? {
        if let date = isoWithFraction.date(from: iso) { return date }
        return isoPlain.date(from: iso)
    }

    /// Sum calories/protein/carbs/fat across entries on `key`'s local day.
    static func sumForDay(_ entries: [FoodEntry], key: String) -> DailyTotals {
        var totals = DailyTotals.zero
        for entry in entries where entryDayKey(entry.loggedAt) == key {
            totals.calories += entry.calories
            totals.proteinG += entry.proteinG
            totals.carbsG += entry.carbsG
            totals.fatG += entry.fatG
        }
        return totals
    }

    /// Roll up one local day against the goals into a `DayHistory`.
    static func dayHistory(_ entries: [FoodEntry], key: String, goals: Goals) -> DayHistory {
        let totals = sumForDay(entries, key: key)
        let loggedAnything = totals.calories > 0 || totals.proteinG > 0
        let caloriesHit = loggedAnything && goals.calorieGoal > 0 && totals.calories <= goals.calorieGoal
        let proteinHit = goals.proteinGoal > 0 && totals.proteinG >= goals.proteinGoal
        return DayHistory(
            date: key,
            totals: totals,
            loggedAnything: loggedAnything,
            caloriesHit: caloriesHit,
            proteinHit: proteinHit,
            hit: caloriesHit && proteinHit
        )
    }

    /// The ordered local day keys for the last `rangeDays` days, oldest first, ending today.
    static func recentDayKeys(_ rangeDays: Int) -> [String] {
        let n = max(0, rangeDays)
        guard n > 0 else { return [] }
        let calendar = Calendar.current
        let today = Date()
        return (0..<n).compactMap { i in
            calendar.date(byAdding: .day, value: -(n - 1 - i), to: today).map { dayKey($0) }
        }
    }

    /// A meal name normalized for dedupe / "is this already saved?" checks: trimmed, lowercased, inner
    /// whitespace collapsed. Display still uses the original casing.
    static func normalizeName(_ name: String) -> String {
        let lowered = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowered.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Derive recent meals from the entry log: group by normalized name, keep each group's newest
    /// macros, count occurrences, exclude any name that's already an explicit saved meal. Sorted
    /// most-used to most-recent. Purely local.
    static func deriveRecents(entries: [FoodEntry], savedMeals: [SavedMeal]) -> [RecentMeal] {
        let savedNames = Set(savedMeals.map { normalizeName($0.name) })
        var order: [String] = []
        var byName: [String: RecentMeal] = [:]

        for entry in entries {
            let norm = normalizeName(entry.name)
            if norm.isEmpty || savedNames.contains(norm) { continue }
            if var existing = byName[norm] {
                existing.useCount += 1
                if entry.loggedAt > existing.lastUsedAt {
                    existing.name = entry.name
                    existing.calories = entry.calories
                    existing.proteinG = entry.proteinG
                    existing.carbsG = entry.carbsG
                    existing.fatG = entry.fatG
                    existing.lastUsedAt = entry.loggedAt
                }
                byName[norm] = existing
            } else {
                order.append(norm)
                byName[norm] = RecentMeal(
                    name: entry.name,
                    calories: entry.calories,
                    proteinG: entry.proteinG,
                    carbsG: entry.carbsG,
                    fatG: entry.fatG,
                    useCount: 1,
                    lastUsedAt: entry.loggedAt
                )
            }
        }

        return order.compactMap { byName[$0] }.sorted { a, b in
            if a.useCount != b.useCount { return a.useCount > b.useCount }
            return a.lastUsedAt > b.lastUsedAt
        }
    }

    /// Current + longest streak with one fixed goals value for every day: the pre-versioning shape, kept
    /// for callers/tests that don't carry a timeline.
    static func streakSummary(entries: [FoodEntry], goals: Goals) -> (current: Int, longest: Int) {
        streakSummary(entries: entries) { _ in goals }
    }

    /// Current + longest streak of fully-hit days across the whole entry history, each day judged
    /// against `goalsFor(itsDayKey)`. The current streak counts back from today (an un-hit today
    /// doesn't yet break the run); the longest is the maximum consecutive run across all logged days.
    static func streakSummary(entries: [FoodEntry], goalsFor: (String) -> Goals) -> (current: Int, longest: Int) {
        let keysWithEntries = Set(entries.compactMap { entryDayKey($0.loggedAt) }).sorted()
        guard let first = keysWithEntries.first else { return (0, 0) }

        var hitByKey: [String: Bool] = [:]
        for key in keysWithEntries {
            hitByKey[key] = dayHistory(entries, key: key, goals: goalsFor(key)).hit
        }

        let todayKey = dayKey(Date())
        var longest = 0
        var run = 0
        for key in calendarKeysBetween(start: first, end: todayKey) {
            if hitByKey[key] == true {
                run += 1
                if run > longest { longest = run }
            } else {
                run = 0
            }
        }

        let calendar = Calendar.current
        var cursor = Date()
        if hitByKey[dayKey(cursor)] != true {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        var current = 0
        while hitByKey[dayKey(cursor)] == true {
            current += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }

        return (current, longest)
    }

    /// Every local day key from `start` to `end` inclusive, oldest first (consecutive calendar days).
    /// Guarded against an unbounded loop on malformed input (~10y of days).
    static func calendarKeysBetween(start: String, end: String) -> [String] {
        let parts = start.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return [] }
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        guard var cursor = calendar.date(from: components) else { return [] }

        var out: [String] = []
        var guardCount = 0
        while dayKey(cursor) <= end && guardCount < 4000 {
            out.append(dayKey(cursor))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
            guardCount += 1
        }
        return out
    }
}
