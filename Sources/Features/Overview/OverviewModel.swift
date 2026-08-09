import Observation
import SwiftUI

@MainActor
@Observable
final class OverviewModel {
    /// The selected day, as a local YYYY-MM-DD key. Defaults to the AppModel's selected date (today in
    /// production, the reference day in `.sample`).
    var selectedDayKey: String

    /// Held, not snapshotted, so the dashboard stays live as profile/connection flags change
    /// elsewhere. `AppModel` and its stores are `@Observable`, so SwiftUI re-renders when they change.
    private let appModel: AppModel
    private var nutrition: NutritionStore { appModel.nutritionStore }

    var profile: Profile? { appModel.profile }
    private var whoopLinked: Bool { appModel.whoopLinked }

    /// Whether this is the seeded demo container. Gates SampleData-backed placeholder surfaces
    /// (goal pace, recovery trend) so a real/fresh user never sees seeded data as their own.
    /// TODO(Whoop projection): drop the gate once these read live data.
    var usesSampleData: Bool { appModel.usesSampleData }

    init(appModel: AppModel) {
        self.appModel = appModel
        self.selectedDayKey = DateStrip.toKey(appModel.selectedDate)
    }

    /// The 7 Sun→Sat day keys of the selected week (the carousel's `days`).
    var weekKeys: [String] { DateStrip.currentWeekKeys(containing: selectedDate) }

    /// The selected day as a `Date` (local midnight), for the nutrition store's per-day queries.
    private var selectedDate: Date {
        let parts = selectedDayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return Date() }
        var c = DateComponents()
        c.year = parts[0]; c.month = parts[1]; c.day = parts[2]
        return Calendar.current.date(from: c) ?? Date()
    }

    var isToday: Bool { selectedDayKey == DateStrip.toKey(Date()) }

    /// A short "Mon 3" label for the selected day (day-scoped card headers + the recovery card).
    var shortDayLabel: String { Format.shortDayLabel(selectedDayKey) }

    var profileName: String? { profile?.name }

    /// The selected day's summed food totals.
    var dayTotals: DailyTotals {
        let entries = nutrition.entries
        let date = selectedDate
        let key = NutritionStore.dayKey(date)
        if let cache = dayTotalsCache, cache.key == key, cache.entries == entries { return cache.totals }
        let totals = nutrition.totalsForDay(date)
        dayTotalsCache = (entries, key, totals)
        return totals
    }
    @ObservationIgnored
    private var dayTotalsCache: (entries: [FoodEntry], key: String, totals: DailyTotals)?

    /// Exposed (was private) so Overview's calories-left card can read the targets.
    var goals: Goals { nutrition.goals }
    var currentStreak: Int { streaks.current }
    var longestStreak: Int { streaks.longest }

    /// Current + longest streak via one `streakSummary` pass. The store's `currentStreak` /
    /// `longestStreak` each scan full history, so the dashboard shares a single memoized call.
    private var streaks: (current: Int, longest: Int) {
        let entries = nutrition.entries
        let timeline = nutrition.goalsTimeline
        let todayKey = NutritionStore.dayKey(Date())
        if let cache = streaksCache, cache.entries == entries, cache.timeline == timeline,
           cache.todayKey == todayKey {
            return cache.value
        }
        let value = nutrition.streakSummary()
        streaksCache = (entries, timeline, todayKey, value)
        return value
    }
    @ObservationIgnored
    private var streaksCache: (entries: [FoodEntry], timeline: [GoalsVersion], todayKey: String, value: (current: Int, longest: Int))?

    /// Map of day key → "hit both goals that day" over a 60-day window (enough for the carousel dots
    /// and week adherence row; a 365-day scan lagged the dashboard). Read twice per render, so
    /// memoized: recomputed only when the log, goals, or today change.
    private var hitByKey: [String: Bool] {
        let entries = nutrition.entries
        let timeline = nutrition.goalsTimeline
        let todayKey = NutritionStore.dayKey(Date())
        if let cache = hitByKeyCache, cache.entries == entries, cache.timeline == timeline,
           cache.todayKey == todayKey {
            return cache.value
        }
        var map: [String: Bool] = [:]
        for day in nutrition.dailyHistory(60) { map[day.date] = day.hit }
        hitByKeyCache = (entries, timeline, todayKey, map)
        return map
    }
    @ObservationIgnored
    private var hitByKeyCache: (entries: [FoodEntry], timeline: [GoalsVersion], todayKey: String, value: [String: Bool])?

    /// Per-day data dot for the carousel: any day that hit both goals shows a dot.
    var adherenceByDay: [String: Bool] { hitByKey }

    /// Ordered Sun→Sat "hit both goals" flags for the adherence dot row.
    var weekHits: [Bool] {
        let hits = hitByKey
        return weekKeys.map { hits[$0] == true }
    }

    /// The selected day's Whoop snapshot, or nil when Whoop isn't linked or that day has no data.
    /// The demo container reads `SampleData.whoopSummary` on the reference day; real users get the
    /// live snapshot fetched by `loadWhoopSummary()`.
    var whoopSummary: WhoopSummary? {
        guard whoopLinked else { return nil }
        if usesSampleData {
            return selectedDayKey == DateStrip.toKey(SampleData.referenceDate) ? SampleData.whoopSummary : nil
        }
        return liveWhoopDayKey == selectedDayKey ? liveWhoopSummary : nil
    }

    /// The live snapshot + the day it belongs to (observed, so the hero re-renders when a fetch lands).
    private(set) var liveWhoopSummary: WhoopSummary?
    private(set) var liveWhoopDayKey: String?

    /// Fetch the selected day's live Whoop snapshot for real linked users (no-op for the demo
    /// container). Re-fired by the screen's `.task(id: selectedDayKey)` on each day scrub; the
    /// client's 15-min cache, in-flight de-dup, and backoff keep repeat calls cheap.
    func loadWhoopSummary() async {
        guard whoopLinked, !usesSampleData else { return }
        let day = selectedDayKey
        let summary = await appModel.whoop.summary(date: isToday ? nil : day, force: false)
        guard day == selectedDayKey else { return }
        liveWhoopSummary = summary
        liveWhoopDayKey = day
    }

    /// The horizontal metric row beneath the hero: Total burned · Steps · Weight · Calories left ·
    /// Protein (recovery/HRV/RHR/sleep/strain live in the hero ring and stat cards). Each item shows
    /// the user's own value with a per-metric hue and a short sparkline of their recent trend.
    var metrics: [OverviewMetric] {
        let whoop = whoopSummary
        let caloriesRemaining = max(0, goals.calorieGoal - dayTotals.calories)
        var items: [OverviewMetric] = []

        if let calories = whoop?.calories {
            items.append(OverviewMetric(
                key: "calories-burned", icon: "flame.fill", title: "Total burned",
                value: Format.int(calories), unit: "kcal",
                accent: Theme.Chart.calories, sparkline: usesSampleData ? Self.burnTrend : []
            ))
        }
        if let steps = whoop?.steps {
            let stepProgress = goals.stepsGoal > 0
                ? min(1, Double(steps.count) / Double(goals.stepsGoal))
                : nil
            items.append(OverviewMetric(
                key: "steps", icon: "figure.walk", title: "Steps",
                value: Format.int(Double(steps.count)), unit: nil,
                accent: Theme.Chart.activity,
                caption: "\(Format.int(Double(goals.stepsGoal))) goal",
                sparkline: usesSampleData ? Self.stepsTrend : [],
                progress: stepProgress
            ))
        }

        if let profile {
            items.append(OverviewMetric(
                key: "weight", icon: "scalemass.fill", title: "Weight",
                value: Format.oneDecimal(Units.kgToLb(profile.weightKg)), unit: "lb",
                accent: Theme.Chart.sleep, caption: "from profile",
                sparkline: usesSampleData ? Self.weightTrend : []
            ))
        }

        let week = weekNutritionSeries
        items.append(OverviewMetric(
            key: "calories", icon: "fork.knife", title: "Calories left",
            value: Format.int(caloriesRemaining), unit: "kcal",
            accent: Theme.Colors.tint, caption: "\(Format.int(goals.calorieGoal)) goal",
            sparkline: usesSampleData ? Self.caloriesLeftTrend : week.caloriesLeft
        ))
        items.append(OverviewMetric(
            key: "protein", icon: "bolt.fill", title: "Protein",
            value: Format.int(dayTotals.proteinG), unit: "g",
            accent: Theme.Chart.protein, caption: "\(Format.int(goals.proteinGoal)) g goal",
            sparkline: usesSampleData ? Self.proteinTrend : week.protein
        ))

        return items
    }

    /// 7-day sparkline series from the user's food log (oldest → today), or empty until at least one
    /// of the last 7 days has a log. A fresh user must never see a fabricated trend. Memoized like
    /// the other rollups (a 7-day scan, read twice per render).
    private var weekNutritionSeries: (caloriesLeft: [Double], protein: [Double]) {
        let entries = nutrition.entries
        let timeline = nutrition.goalsTimeline
        let todayKey = NutritionStore.dayKey(Date())
        if let cache = weekSeriesCache, cache.entries == entries, cache.timeline == timeline,
           cache.todayKey == todayKey {
            return cache.value
        }
        let week = nutrition.dailyHistory(7)
        let value: ([Double], [Double]) = week.contains(where: \.loggedAnything)
            ? (week.map { max(0, nutrition.goals(on: $0.date).calorieGoal - $0.totals.calories) },
               week.map(\.totals.proteinG))
            : ([], [])
        weekSeriesCache = (entries, timeline, todayKey, value)
        return value
    }
    @ObservationIgnored
    private var weekSeriesCache: (entries: [FoodEntry], timeline: [GoalsVersion], todayKey: String, value: (caloriesLeft: [Double], protein: [Double]))?

    private static let burnTrend: [Double] = [2410, 2705, 2280, 2520, 2390, 2880, 2658]
    private static let stepsTrend: [Double] = [6100, 5400, 7200, 4800, 6900, 8100, 5322]
    private static let weightTrend: [Double] = [186.4, 186.0, 185.6, 185.2, 184.9, 184.6, 184.2]
    private static let caloriesLeftTrend: [Double] = [620, 410, 880, 240, 700, 150, 520]
    private static let proteinTrend: [Double] = [168, 192, 150, 205, 180, 188, 192]

    var recoveryTrendValues: [Double] { SampleData.recoveryTrend.compactMap { $0.value } }
    var recoveryTrendLabels: [String] {
        SampleData.recoveryTrend.map { Format.shortDayLabel($0.date) }
    }
    var recoveryTrendLatest: String? {
        SampleData.recoveryTrend.last?.value.map { "\(Format.int($0))%" }
    }

    /// The user's trailing average recovery % (the "Avg N%" pill).
    var recoveryTrendAverage: Int {
        let v = recoveryTrendValues
        guard !v.isEmpty else { return 0 }
        return Int((v.reduce(0, +) / Double(v.count)).rounded())
    }

    /// The user's typical recovery band (min/max of the recent window), shaded behind the trend line.
    /// Never a clinical "normal range", just the user's own recent spread.
    var recoveryTypicalLow: Double? { recoveryTrendValues.min() }
    var recoveryTypicalHigh: Double? { recoveryTrendValues.max() }

    /// The Goal-Pace card's computed state, evaluated over the user's daily weigh-in series vs. their
    /// dated target. Runs the pure `GoalPaceMath` once; the card just renders the result.
    ///
    /// TODO: wire target weight + date input (onboarding/goals) when the body-weight store lands.
    /// v1 reads the SampleData series + sample target; there's no target-input UX yet, so the card is
    /// populated only in the `.sample` container (a live container correctly yields "not enough data").
    var goalPace: GoalPaceState? {
        guard appModel.usesSampleData else { return nil }
        return samplePace
    }

    /// The sample-container pace evaluation, computed once. Every input is a SampleData constant
    /// (including the `today` anchor), so the result is deterministic; re-running the EWMA and
    /// month-label formatting each render was waste.
    @ObservationIgnored
    private lazy var samplePace: GoalPaceState? = GoalPaceState.evaluate(
        weightHistoryLb: SampleData.weightHistoryLb,
        lastWeighInKey: DateStrip.toKey(SampleData.referenceDate),
        targetWeightLb: SampleData.goalTargetWeightLb,
        targetDateKey: SampleData.goalTargetDateKey,
        today: SampleData.referenceDate
    )
}

/// One card in the Overview metric row (Total burned · Steps · Weight · Calories left · Protein):
/// a label-forward card with a gradient sparkline of the user's recent values. Display-only.
struct OverviewMetric: Identifiable {
    let key: String
    let icon: String
    let title: String
    let value: String
    var unit: String?
    let accent: Color
    var caption: String?
    /// The recent series the card renders as a gradient mini-line. Empty → no sparkline.
    var sparkline: [Double] = []
    /// Progress 0…1 against a goal for tiles that have one (steps vs `goals.stepsGoal`). `nil` →
    /// no goal bar.
    var progress: Double? = nil
    var id: String { key }
}
