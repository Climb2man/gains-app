import SwiftUI

struct SleepDetailScreen: View {
    @Environment(AppModel.self) private var appModel

    /// The day to show (YYYY-MM-DD, local).
    let date: String

    private enum Phase: Equatable { case loading, ready, empty, notLinked }

    @State private var phase: Phase = .loading
    @State private var detail: SleepDetail?
    /// Respiratory rate (breaths/min). The sleep endpoint omits it, so we read it from the same day's
    /// recovery summary; the client de-dupes that fetch and reuses the cached snapshot.
    @State private var respiratoryRate: Double?
    @State private var refreshing = false

    private static let awakeColor = Theme.Colors.labelTertiary
    private static let lightColor = Theme.Chart.fat
    private static let swsColor = Theme.Chart.sleep
    private static let remColor = Theme.Chart.recovery

    private static let highColor = Theme.Colors.warning
    private static let mediumColor = Theme.Chart.calories
    private static let lowColor = Theme.Chart.strain

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                switch phase {
                case .notLinked:
                    ConnectWhoopState(
                        title: "Connect Whoop in Settings",
                        message: "Link your Whoop account to see last night's sleep stages, efficiency, and performance here."
                    )
                case .loading:
                    SkeletonCard()
                case .empty:
                    WhoopNoDataState(
                        title: "No sleep data yet",
                        message: "Once your Whoop has synced last night's sleep it'll show up here. Pull down or tap below to try again.",
                        refreshing: refreshing,
                        onRefresh: { Task { await refresh() } }
                    )
                case .ready:
                    if let detail {
                        content(detail)
                    }
                }
            }
            .padding(Theme.Spacing.xl)
            .padding(.bottom, 40)
        }
        .background(Theme.Colors.background)
        .scrollIndicators(.hidden)
        .navigationTitle("Sleep")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await refresh() }
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ detail: SleepDetail) -> some View {
        HoursOfSleepCard(detail: detail)
        StageBreakdownCard(detail: detail, colors: stageColors)
        MetricTilesRow(detail: detail, respiratoryRate: respiratoryRate)
        SleepStressCard(detail: detail, colors: stressColors)
    }

    private var stageColors: StageColors {
        StageColors(awake: Self.awakeColor, light: Self.lightColor, sws: Self.swsColor, rem: Self.remColor)
    }

    private var stressColors: StressBandColors {
        StressBandColors(high: Self.highColor, medium: Self.mediumColor, low: Self.lowColor)
    }

    private func load() async {
        if appModel.usesSampleData {
            detail = SampleData.sleepDetail
            respiratoryRate = SampleData.whoopSummary.respiratoryRate
            phase = hasStageData(SampleData.sleepDetail) ? .ready : .empty
            return
        }
        guard await appModel.whoop.isLinked() else {
            phase = .notLinked
            return
        }
        phase = .loading
        await fetch()
    }

    private func refresh() async {
        if appModel.usesSampleData { return }
        guard await appModel.whoop.isLinked() else {
            phase = .notLinked
            return
        }
        refreshing = true
        await fetch()
        refreshing = false
    }

    private func fetch() async {
        let next = await appModel.whoop.sleepDetail(date: date)
        let summary = await appModel.whoop.summary(date: date, force: false)
        detail = next
        respiratoryRate = summary?.respiratoryRate
        phase = (next != nil && hasStageData(next)) ? .ready : .empty
    }

    /// True when the detail has at least one non-nil stage duration (something to draw).
    private func hasStageData(_ detail: SleepDetail?) -> Bool {
        guard let s = detail?.stages else { return false }
        return s.remMs != nil || s.swsMs != nil || s.lightMs != nil || s.wakeMs != nil
            || detail?.totalSleepMs != nil
    }
}

struct StageColors { let awake, light, sws, rem: Color }
struct StressBandColors { let high, medium, low: Color }

private struct HoursOfSleepCard: View {
    let detail: SleepDetail

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let hours = detail.hours ?? WhoopFormat.msClock(detail.totalSleepMs)
        let perf = detail.performancePctExt ?? detail.performancePct
        let curve = detail.hrCurve ?? []

        Card(metricAccent: Theme.Chart.sleep) {
            Txt("HOURS OF SLEEP", variant: .sectionHeader, color: .labelSecondary)

            HStack(alignment: .center, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(hours)
                        .font(Theme.Font.heroNumber)
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .foregroundStyle(Theme.Colors.label)
                    if let beneath = needSubtext {
                        Txt(beneath, variant: .footnote, color: .labelTertiary)
                    }
                }
                Spacer(minLength: 0)
                GradientRing(
                    progress: (perf ?? 0) / 100,
                    title: perf.map { "\(Int($0.rounded()))%" } ?? "–",
                    caption: "performance",
                    gradient: Theme.Chart.gradientStops(for: Theme.Chart.sleep),
                    track: Theme.Chart.ringTrack(for: Theme.Chart.sleep),
                    lineWidth: 12, size: 116,
                    animated: !reduceMotion
                )
            }

            if !curve.isEmpty {
                let values = curve.map(\.bpm)
                let labels = curve.enumerated().map { i, p in
                    (i == 0 || i == curve.count - 1) ? p.clock : ""
                }
                Txt("Overnight heart rate", variant: .footnote, color: .labelTertiary)
                InteractiveLineChart(
                    values: values, labels: labels,
                    color: Theme.Chart.heartrate,
                    width: WhoopChart.cardWidth, height: 170,
                    format: { "\(Int($0.rounded())) bpm" }
                )
            }
        }
    }

    /// The 30-day baseline and/or sleep-needed shown beneath the hours, each labeled with its source
    /// so it reads as a comparison figure, not a target. Nil when neither is set.
    private var needSubtext: String? {
        var parts: [String] = []
        if let needed = detail.hoursNeeded { parts.append("\(needed) needed") }
        if let baseline = detail.hoursBaseline { parts.append("30-day avg \(baseline)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private struct StageBreakdownCard: View {
    let detail: SleepDetail
    let colors: StageColors

    private struct Row: Identifiable {
        let label: String; let color: Color; let ms, pct: Double?; let range: SleepStageRange?
        var id: String { label }
    }

    var body: some View {
        let stages = detail.stages
        let durationDisplay = detail.durationInBed ?? WhoopFormat.msClock(detail.timeInBedMs)
        let total = detail.totalSleepMs
        let rows = [
            Row(label: "AWAKE", color: colors.awake, ms: stages.wakeMs, pct: stages.wakePct, range: stages.wakeRange),
            Row(label: "LIGHT", color: colors.light, ms: stages.lightMs, pct: stages.lightPct, range: stages.lightRange),
            Row(label: "SWS (DEEP)", color: colors.sws, ms: stages.swsMs, pct: stages.swsPct, range: stages.swsRange),
            Row(label: "REM", color: colors.rem, ms: stages.remMs, pct: stages.remPct, range: stages.remRange),
        ]
        let columns = [GridItem(.flexible(), spacing: Theme.Spacing.md),
                       GridItem(.flexible(), spacing: Theme.Spacing.md)]

        Card {
            HStack(alignment: .firstTextBaseline) {
                Txt("TYPICAL RANGE", variant: .sectionHeader, color: .labelSecondary)
                Spacer(minLength: 0)
                Txt("DURATION \(durationDisplay)", variant: .footnote, color: .labelTertiary)
            }

            SleepStagesChart(
                stages: hypnogram(detail),
                colors: [colors.awake, colors.rem, colors.light, colors.sws],
                width: WhoopChart.cardWidth, height: 90
            )

            LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                ForEach(rows) { r in
                    StatRingCard(
                        label: r.label.capitalized,
                        value: WhoopFormat.msClock(r.ms),
                        percent: stagePctDisplay(r.pct, r.ms, total),
                        progress: stageFraction(r.pct, r.ms, total),
                        color: r.color
                    )
                }
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                ForEach(rows) { r in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        TypicalRangeBar(
                            value: stageFraction(r.pct, r.ms, total),
                            rangeLow: r.range?.lower ?? 0,
                            rangeHigh: r.range?.upper ?? 0,
                            color: r.color,
                            label: r.label,
                            pctDisplay: stagePctDisplay(r.pct, r.ms, total),
                            timeDisplay: WhoopFormat.msClock(r.ms),
                            width: WhoopChart.cardWidth,
                            animated: true
                        )
                        Txt("vs your typical", variant: .footnote, color: .labelTertiary)
                    }
                }
            }
            .padding(.top, Theme.Spacing.xs)
        }
    }

    /// A representative hypnogram from the night's stage shares: proportional run lengths over a fixed
    /// slot count so block widths match the durations. Indicative shape only. Whoop's per-slot
    /// staging isn't carried.
    private func hypnogram(_ detail: SleepDetail) -> [Int] {
        let stages = detail.stages
        let total = detail.totalSleepMs
        let shares: [(Int, Double)] = [
            (0, stageFraction(stages.wakePct, stages.wakeMs, total)),
            (1, stageFraction(stages.remPct, stages.remMs, total)),
            (2, stageFraction(stages.lightPct, stages.lightMs, total)),
            (3, stageFraction(stages.swsPct, stages.swsMs, total)),
        ]
        let slots = 40
        let order = [2, 3, 2, 1, 0, 2, 3, 2, 1, 2]
        var result: [Int] = []
        var counts = Dictionary(uniqueKeysWithValues: shares.map { ($0.0, Int(($0.1 * Double(slots)).rounded())) })
        var idx = 0
        while result.count < slots {
            let stage = order[idx % order.count]
            if (counts[stage] ?? 0) > 0 {
                result.append(stage)
                counts[stage]? -= 1
            } else if counts.values.allSatisfy({ $0 <= 0 }) {
                break
            }
            idx += 1
        }
        return result.isEmpty ? order : result
    }

    /// A stage's fraction-of-total in [0,1]: prefer Whoop's verbatim %, else derive from duration.
    private func stageFraction(_ pct: Double?, _ ms: Double?, _ total: Double?) -> Double {
        if let pct { return clamp01(pct / 100) }
        if let ms, let total, total > 0 { return clamp01(ms / total) }
        return 0
    }

    /// A stage's percentage label ("22%"): the verbatim pct, else derived, else "–".
    private func stagePctDisplay(_ pct: Double?, _ ms: Double?, _ total: Double?) -> String {
        if let pct { return "\(Int(pct.rounded()))%" }
        if let ms, let total, total > 0 { return "\(Int((ms / total * 100).rounded()))%" }
        return "–"
    }

    private func clamp01(_ v: Double) -> Double { max(0, min(1, v)) }
}

private struct MetricTilesRow: View {
    let detail: SleepDetail
    let respiratoryRate: Double?

    private struct Tile: Identifiable {
        let id: String; let icon, label, value: String; var unit: String?; var accent: Color
    }

    var body: some View {
        let tiles: [Tile] = [
            Tile(id: "restorative", icon: "bolt.heart.fill", label: "Restorative",
                 value: detail.restorative ?? WhoopFormat.msClockOrDash(detail.restorativeMs),
                 unit: nil, accent: Theme.Chart.recovery),
            Tile(id: "latency", icon: "hourglass", label: "Sleep latency",
                 value: detail.latency ?? WhoopFormat.msClockOrDash(detail.latencyMs),
                 unit: nil, accent: Theme.Chart.sleep),
            Tile(id: "wake", icon: "eye.fill", label: "Wake events",
                 value: WhoopFormat.countOrDash(detail.wakeEvents ?? detail.disturbances),
                 unit: nil, accent: Theme.Chart.calories),
            Tile(id: "efficiency", icon: "gauge.with.dots.needle.67percent", label: "Efficiency",
                 value: pctValue(detail.efficiencyPctExt ?? detail.efficiencyPct), unit: "%",
                 accent: Theme.Chart.activity),
            Tile(id: "consistency", icon: "repeat", label: "Consistency",
                 value: pctValue(detail.consistencyPctExt ?? detail.consistencyPct), unit: "%",
                 accent: Theme.Chart.strain),
            Tile(id: "respiratory", icon: "lungs.fill", label: "Respiratory",
                 value: respiratoryRate.map { WhoopFormat.oneDecimal($0) } ?? "–",
                 unit: respiratoryRate != nil ? "rpm" : nil, accent: Theme.Chart.heartrate),
        ]

        let columns = [GridItem(.flexible(), spacing: Theme.Spacing.md),
                       GridItem(.flexible(), spacing: Theme.Spacing.md)]
        LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
            ForEach(tiles) { tile in
                MetricCard(icon: tile.icon, title: tile.label, value: tile.value,
                                unit: tile.unit, accent: tile.accent)
            }
        }
    }

    /// A whole-number percent ("92"), or "–" when absent. The unit is shown separately by the card.
    private func pctValue(_ n: Double?) -> String {
        guard let n else { return "–" }
        return String(Int(n.rounded()))
    }
}

private struct SleepStressCard: View {
    let detail: SleepDetail
    let colors: StressBandColors

    private struct Band: Identifiable {
        let label: String; let color: Color; let band: SleepStressBand?
        var id: String { label }
    }

    var body: some View {
        if let stress = detail.sleepStress {
            let overall = stress.overallPct.map { "\(Int($0.rounded()))%" } ?? "–"
            let curve = stress.curve ?? []
            let bands = [
                Band(label: "High", color: colors.high, band: stress.breakdown?.high),
                Band(label: "Medium", color: colors.medium, band: stress.breakdown?.medium),
                Band(label: "Low", color: colors.low, band: stress.breakdown?.low),
            ]
            let hasBreakdown = bands.contains { $0.band != nil }

            Card(metricAccent: Theme.Chart.calories) {
                HStack(alignment: .firstTextBaseline) {
                    Txt("SLEEP STRESS", variant: .sectionHeader, color: .labelSecondary)
                    Spacer(minLength: 0)
                    Txt(overall, variant: .title2)
                }

                if !curve.isEmpty {
                    let values = curve.map(\.level)
                    let labels = curve.enumerated().map { i, p in
                        (i == 0 || i == curve.count - 1) ? p.clock : ""
                    }
                    let baseline = stress.overallPct.map { $0 / 100 * WhoopScreen.stressMax }
                    InteractiveLineChart(
                        values: values, labels: labels,
                        color: Theme.Chart.calories,
                        width: WhoopChart.cardWidth, height: 160,
                        format: { WhoopFormat.oneDecimal($0) }
                    )
                    if let baseline {
                        Txt("30-day baseline \(WhoopFormat.oneDecimal(baseline)) / \(Int(WhoopScreen.stressMax))",
                            variant: .footnote, color: .labelTertiary)
                    }
                }

                if hasBreakdown {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        ForEach(bands) { entry in
                            if let band = entry.band {
                                BandRow(label: entry.label, color: entry.color, band: band)
                            }
                        }
                    }
                    .padding(.top, Theme.Spacing.xs)
                }
                Txt("Overnight sleep stress", variant: .footnote, color: .labelTertiary)
            }
        }
    }
}

/// One sleep-stress band row: a label + time header over a progress bar filled to the band's share.
private struct BandRow: View {
    let label: String
    let color: Color
    let band: SleepStressBand

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                HStack(spacing: Theme.Spacing.sm) {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Txt(label, variant: .footnote, color: .labelSecondary)
                    Txt(band.pctDisplay, variant: .footnote)
                }
                Spacer(minLength: 0)
                Txt(band.timeDisplay, variant: .footnote, color: .labelTertiary)
            }
            ProgressBar(progress: fractionFromPctDisplay(band.pctDisplay), color: color, height: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(band.pctDisplay), \(band.timeDisplay)")
    }

    /// Parse a verbatim "12%" display into a [0,1] fraction for the bar fill; 0 when unparseable.
    private func fractionFromPctDisplay(_ display: String) -> Double {
        let cleaned = display.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
        guard let n = Double(cleaned) else { return 0 }
        return max(0, min(1, n / 100))
    }
}

#if DEBUG
#Preview("Sleep detail (populated)") {
    NavigationStack {
        SleepDetailScreen(date: "2026-06-06")
    }
    .environment(AppModel.sample)
}
#endif
