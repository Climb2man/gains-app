import Observation
import SwiftUI

@MainActor
@Observable
final class WhoopViewModel {
    /// Coarse load phase for the whole tab. `notLinked` shows the connect card; `empty` the per-day
    /// no-data card; `ready` the populated content.
    enum Phase: Equatable { case loading, ready, empty, notLinked }

    private(set) var phase: Phase = .loading
    private(set) var summary: WhoopSummary?
    private(set) var stress: StressDetail?
    private(set) var strain: StrainDetail?
    /// The night's per-minute overnight HR curve. The mobile API exposes no all-day continuous HR
    /// series, so this is the only "heart rate over time" data; nil/empty keeps the zones-only layout.
    private(set) var sleep: SleepDetail?
    /// The current strap heart rate (LIVE_HR tile), refreshed while the tab is visible. nil → hidden.
    private(set) var liveHr: WhoopLiveHr?
    /// Whoop's own behavior→outcome impacts ("Alcohol · −12%"), restated verbatim. Empty → no card.
    private(set) var behaviorImpacts: [WhoopBehaviorImpact] = []
    /// Whoop's sleep-need coaching for tonight (recommended time-in-bed + breakdown). nil → hidden.
    private(set) var sleepNeed: WhoopSleepNeed?
    /// True while a pull-to-refresh / header-refresh is in flight (drives the spinner + button state).
    private(set) var refreshing = false

    private let appModel: AppModel
    /// The day the tab is scoped to (YYYY-MM-DD, local). Defaults to the AppModel's selected date.
    private(set) var day: String

    init(appModel: AppModel) {
        self.appModel = appModel
        self.day = Self.dayKey(appModel.selectedDate)
    }

    /// First load (or a date change): resolve the link state, then the snapshot and deep-dives. Safe
    /// to call again. The sample container short-circuits to seeded data.
    func load() async {
        if appModel.usesSampleData {
            applySample()
            return
        }
        guard await appModel.whoop.isLinked() else {
            phase = .notLinked
            return
        }
        if summary == nil { phase = .loading }
        await fetch(force: false)
    }

    /// Pull-to-refresh: re-pulls the snapshot and both deep-dives. The client de-dupes and backs off,
    /// so this can't spam the API.
    func refresh() async {
        if appModel.usesSampleData { return }
        guard await appModel.whoop.isLinked() else {
            phase = .notLinked
            return
        }
        refreshing = true
        await fetch(force: true)
        refreshing = false
    }

    /// Re-scope the tab to a different day, reloading its data.
    func select(day newDay: String) async {
        guard newDay != day else { return }
        day = newDay
        await load()
    }

    private func fetch(force: Bool) async {
        let nextSummary = await appModel.whoop.summary(date: day, force: force)
        let nextStress = await appModel.whoop.stressDetail(date: day, force: force)
        let nextStrain = await appModel.whoop.strainDetail(date: day)
        let nextSleep = await appModel.whoop.sleepDetail(date: day)
        let nextBehavior = await appModel.whoop.behaviorImpacts()
        let nextSleepNeed = await appModel.whoop.sleepNeed()
        summary = nextSummary
        stress = nextStress
        strain = nextStrain
        sleep = nextSleep
        behaviorImpacts = nextBehavior
        sleepNeed = nextSleepNeed
        phase = nextSummary == nil ? .empty : .ready
    }

    /// Poll the live strap HR while the tab is on screen, from a `.task` cancelled on disappear. The
    /// sample container shows a fixed value; a real build polls every 3s. Only today streams live.
    func streamLiveHeartRate() async {
        if appModel.usesSampleData {
            liveHr = WhoopLiveHr(bpm: 72, zone: 1, isRecording: true, lastUpdated: nil)
            return
        }
        guard day == Self.dayKey(Date()), await appModel.whoop.isLinked() else { liveHr = nil; return }
        while !Task.isCancelled {
            liveHr = await appModel.whoop.liveHeartRate()
            try? await Task.sleep(for: .seconds(3))
        }
    }

    private func applySample() {
        summary = SampleData.whoopSummary
        stress = SampleData.stressDetail
        strain = SampleData.strainDetail
        sleep = SampleData.sleepDetail
        behaviorImpacts = SampleData.behaviorImpacts
        sleepNeed = SampleData.sleepNeed
        phase = .ready
    }

    /// The header subtitle: freshness only ("as of <recovery time>"). The source isn't restated since
    /// the tab is already titled "Whoop".
    var subtitle: String {
        guard phase != .notLinked else { return "Pull down to refresh" }
        let asOf = WhoopFormat.asOfLabel(summary?.recordedAt, summary?.updatedAt)
        return asOf.isEmpty ? "Pull down to refresh" : asOf.prefix(1).uppercased() + asOf.dropFirst()
    }

    /// Local YYYY-MM-DD for a date (matches the nutrition store, no UTC drift).
    static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
