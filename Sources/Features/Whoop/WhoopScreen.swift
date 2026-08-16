import SwiftUI

struct WhoopScreen: View {
    @Environment(AppModel.self) private var appModel
    @State private var model: WhoopViewModel?
    @State private var path = NavigationPath()

    static let strainMax: Double = 21
    static let stressMax: Double = 3

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    if let model {
                        content(model)
                    }
                }
                .padding(Theme.Spacing.xl)
                .padding(.bottom, 80)
            }
            .background(Theme.Colors.background)
            .scrollIndicators(.hidden)
            .navigationTitle("Whoop")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if let model, model.phase != .notLinked {
                    ToolbarItem(placement: .topBarTrailing) {
                        WhoopToolbarRefreshButton(busy: model.refreshing) {
                            Task { await model.refresh() }
                        }
                    }
                }
            }
            .refreshable { await model?.refresh() }
            .navigationDestination(for: WhoopRoute.self) { route in
                switch route {
                case .recovery(let day): RecoveryDetailScreen(date: day)
                case .strain(let day): StrainDetailScreen(date: day)
                case .sleep(let day): SleepDetailScreen(date: day)
                case .stress(let day): StressDetailScreen(date: day)
                case .insights: InsightsScreen()
                case .compare: CompareScreen()
                case .explore: ExploreScreen()
                }
            }
        }
        .task {
            if model == nil { model = WhoopViewModel(appModel: appModel) }
            await model?.load()
            #if DEBUG
            applyDebugRoute()
            #endif
        }
        .task(id: model?.day) { await model?.streamLiveHeartRate() }
        .onChange(of: appModel.selectedDate) { _, date in
            // Same reason as Overview: `WhoopViewModel.init` captured the day once, so the foreground
            // reset to today never reached it and an overnight suspend left the tab on yesterday.
            Task { await model?.select(day: WhoopViewModel.dayKey(date)) }
        }
    }

    #if DEBUG
    /// Screenshot-harness hook: pushes a Whoop route from the `-whoopRoute` launch argument so the
    /// detail screens can be captured headlessly. DEBUG-only, so shipped navigation is unchanged.
    private func applyDebugRoute() {
        guard path.isEmpty, let raw = UserDefaults.standard.string(forKey: "whoopRoute"),
              let day = model?.day else { return }
        switch raw {
        case "recovery": path.append(WhoopRoute.recovery(day: day))
        case "strain": path.append(WhoopRoute.strain(day: day))
        case "sleep": path.append(WhoopRoute.sleep(day: day))
        case "stress": path.append(WhoopRoute.stress(day: day))
        case "insights": path.append(WhoopRoute.insights)
        case "compare": path.append(WhoopRoute.compare)
        case "explore": path.append(WhoopRoute.explore)
        default: break
        }
    }
    #endif

    @ViewBuilder
    private func content(_ model: WhoopViewModel) -> some View {
        switch model.phase {
        case .notLinked:
            ConnectWhoopState(
                title: "Connect Whoop in Settings",
                message: "Link your Whoop account to see your recovery, strain, sleep, stress, and heart rate here every day."
            )
        case .loading:
            SkeletonCard()
            SkeletonCard(lines: 2)
        case .empty:
            WhoopNoDataState(
                title: "No Whoop data for this day",
                message: "Once your Whoop has synced this day it'll show up here. Pull down or tap below to try again.",
                refreshing: model.refreshing,
                onRefresh: { Task { await model.refresh() } }
            )
        case .ready:
            if let summary = model.summary {
                WhoopContent(summary: summary, stress: model.stress, strain: model.strain,
                             sleep: model.sleep, live: model.liveHr,
                             behaviorImpacts: model.behaviorImpacts, sleepNeed: model.sleepNeed,
                             day: model.day)
            }
        }
    }
}

/// The Whoop tab's push destinations: each pillar's deep-dive, scoped to a day.
enum WhoopRoute: Hashable {
    case recovery(day: String)
    case strain(day: String)
    case sleep(day: String)
    case stress(day: String)
    case insights
    case compare
    case explore
}

private struct WhoopContent: View {
    let summary: WhoopSummary
    let stress: StressDetail?
    let strain: StrainDetail?
    let sleep: SleepDetail?
    let live: WhoopLiveHr?
    let behaviorImpacts: [WhoopBehaviorImpact]
    let sleepNeed: WhoopSleepNeed?
    let day: String

    var body: some View {
        PillarRingsCard(summary: summary, day: day)
        RecoveryVitals(summary: summary, day: day)
        StressTeaseCard(stress: stress, day: day)
        SleepCard(summary: summary, need: sleepNeed, day: day)
        HeartRateCard(summary: summary, strain: strain, hrCurve: sleep?.hrCurve ?? [], live: live)
        BehaviorImpactCard(impacts: behaviorImpacts)
        RecoveryTrendsCard()

        SectionCaption(title: "Explore your data")
        InsightsEntryCard()
        CompareEntryCard()
        ExploreEntryCard()
    }
}

/// NavigationLink card pushing the Insights screen. Uses a plain Card, not ActionCard: ActionCard is
/// itself a Button, and a Button nested in a NavigationLink would swallow the tap.
private struct InsightsEntryCard: View {
    var body: some View {
        NavigationLink(value: WhoopRoute.insights) {
            Card(metricAccent: Theme.Chart.recovery) {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.Chart.recovery)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Theme.Chart.recovery.opacity(0.14)))
                    VStack(alignment: .leading, spacing: 2) {
                        Txt("Insights", variant: .bodyEmphasized)
                        Txt("How your metrics move together", variant: .footnote, color: .labelTertiary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Colors.tint)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Insights")
    }
}

/// NavigationLink card pushing the Compare screen. Same plain-Card pattern as the Insights entry: a
/// Button nested in a NavigationLink would swallow the tap.
private struct CompareEntryCard: View {
    var body: some View {
        NavigationLink(value: WhoopRoute.compare) {
            Card(metricAccent: Theme.Chart.sleep) {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "square.on.square")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.Chart.sleep)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Theme.Chart.sleep.opacity(0.14)))
                    VStack(alignment: .leading, spacing: 2) {
                        Txt("Compare", variant: .bodyEmphasized)
                        Txt("Overlay your metrics on one axis", variant: .footnote, color: .labelTertiary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Colors.tint)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Compare")
    }
}

/// NavigationLink card pushing the Explore screen. Same plain-Card pattern as the Insights/Compare
/// entries: a Button nested in a NavigationLink would swallow the tap.
private struct ExploreEntryCard: View {
    var body: some View {
        NavigationLink(value: WhoopRoute.explore) {
            Card(metricAccent: Theme.Chart.activity) {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.Chart.activity)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Theme.Chart.activity.opacity(0.14)))
                    VStack(alignment: .leading, spacing: 2) {
                        Txt("Explore", variant: .bodyEmphasized)
                        Txt("Browse every metric", variant: .footnote, color: .labelTertiary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Colors.tint)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Explore")
    }
}

private struct PillarRingsCard: View {
    let summary: WhoopSummary
    let day: String

    /// Sleep · Recovery · Strain, left to right — the order the day happens in, and the same order
    /// the Overview card uses. Recovery sits in the middle because it is the headline reading and
    /// the other two are its inputs: sleep feeds it, strain spends it.
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            PillarRingLink(route: .sleep(day: day), label: "Sleep detail") {
                PillarRing(
                    label: "SLEEP",
                    progress: (summary.sleepPerformancePct ?? 0) / 100,
                    color: Theme.Chart.sleep,
                    valueText: summary.sleepPerformancePct.map { "\(Int($0.rounded()))%" } ?? "–"
                )
            }
            PillarRingLink(route: .recovery(day: day), label: "Recovery detail") {
                PillarRing(
                    label: "RECOVERY",
                    progress: (summary.recoveryPct ?? 0) / 100,
                    color: WhoopColor.recovery(summary.recoveryPct, state: summary.recoveryState),
                    valueText: summary.recoveryPct.map { "\(Int($0.rounded()))%" } ?? "–"
                )
            }
            PillarRingLink(route: .strain(day: day), label: "Strain detail") {
                PillarRing(
                    label: "STRAIN",
                    progress: min(1, max(0, (summary.dayStrain ?? 0) / WhoopScreen.strainMax)),
                    color: Theme.Chart.strain,
                    valueText: summary.dayStrain.map { WhoopFormat.oneDecimal($0) } ?? "–",
                    subText: "/ \(Int(WhoopScreen.strainMax))"
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.sm)
    }
}

/// A pillar ring wrapped in a NavigationLink, with a brief press scale so the tap reads as live.
private struct PillarRingLink<Content: View>: View {
    let route: WhoopRoute
    let label: String
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed = false

    var body: some View {
        NavigationLink(value: route) {
            content
                .scaleEffect(pressed && !reduceMotion ? 0.96 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: pressed)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }
}

private struct PillarRing: View {
    let label: String
    let progress: Double
    let color: Color
    let valueText: String
    var subText: String?

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            RingChart(progress: progress, size: 92, strokeWidth: 10, color: color) {
                VStack(spacing: 0) {
                    Text(valueText)
                        .font(Theme.Font.statNumber)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Colors.label)
                    if let subText {
                        Text(subText)
                            .font(Theme.Font.footnote)
                            .foregroundStyle(Theme.Colors.labelTertiary)
                    }
                }
            }
            Txt(label, variant: .footnote, color: .labelSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(valueText)")
    }
}

private struct RecoveryVitals: View {
    let summary: WhoopSummary
    let day: String

    /// Which vital's detail sheet is open (nil = none).
    @State private var openVital: Vital?

    private enum Vital: String, Identifiable {
        case hrv, rhr, respiratory
        var id: String { rawValue }
    }

    var body: some View {
        let hrvDelta = WhoopFormat.delta(summary.hrvMs, summary.hrvBaselineMs, unit: "ms")
        let rhrDelta = WhoopFormat.delta(summary.rhrBpm, summary.rhrBaselineBpm, unit: "bpm")
        let columns = [GridItem(.flexible(), spacing: Theme.Spacing.md),
                       GridItem(.flexible(), spacing: Theme.Spacing.md)]

        LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
            if let hrv = summary.hrvMs {
                vitalButton(.hrv) {
                    MetricCard(
                        icon: "waveform.path.ecg", title: "HRV",
                        value: WhoopFormat.oneDecimal(hrv), unit: "ms",
                        trend: trend(hrvDelta?.direction),
                        trendColor: tone(hrvDelta?.direction, lowerIsBetter: false),
                        accent: Theme.Chart.recovery
                    )
                }
            }
            if let rhr = summary.rhrBpm {
                vitalButton(.rhr) {
                    MetricCard(
                        icon: "heart.fill", title: "Resting HR",
                        value: String(Int(rhr.rounded())), unit: "bpm",
                        trend: trend(rhrDelta?.direction),
                        trendColor: tone(rhrDelta?.direction, lowerIsBetter: true),
                        accent: Theme.Chart.heartrate
                    )
                }
            }
            if let rr = summary.respiratoryRate {
                vitalButton(.respiratory) {
                    MetricCard(
                        icon: "lungs.fill", title: "Respiratory",
                        value: WhoopFormat.oneDecimal(rr), unit: "rpm",
                        accent: Theme.Chart.recovery
                    )
                }
            }
        }
        .sheet(item: $openVital) { vital in
            vitalSheet(vital)
                .presentationDetents([.large])
                .presentationCornerRadius(28)
        }
    }

    private func vitalButton(_ vital: Vital, @ViewBuilder _ card: () -> some View) -> some View {
        Button { openVital = vital } label: { card() }
            .buttonStyle(.plain)
    }

    @ViewBuilder
    private func vitalSheet(_ vital: Vital) -> some View {
        switch vital {
        case .hrv:
            metricSheet(title: "HRV", unit: "ms", value: summary.hrvMs,
                        baseline: summary.hrvBaselineMs, color: Theme.Chart.recovery)
        case .rhr:
            metricSheet(title: "Resting HR", unit: "bpm", value: summary.rhrBpm,
                        baseline: summary.rhrBaselineBpm, color: Theme.Chart.heartrate)
        case .respiratory:
            metricSheet(title: "Respiratory rate", unit: "rpm", value: summary.respiratoryRate,
                        baseline: nil, color: Theme.Chart.recovery)
        }
    }

    private func metricSheet(title: String, unit: String, value: Double?, baseline: Double?, color: Color) -> some View {
        let v = value ?? 0
        let base = baseline ?? v
        let series: [Double] = [base, (base + v) / 2, v]
        let bandLow = base * 0.95
        let bandHigh = base * 1.05
        var stats: [MetricStatStrip.Item] = [
            .init(label: "Latest", value: WhoopFormat.oneDecimal(v), unit: unit)
        ]
        if let baseline {
            stats.append(.init(label: "Typical", value: WhoopFormat.oneDecimal(baseline), unit: unit))
        }
        return MetricDetailSheet(
            title: title, value: WhoopFormat.oneDecimal(v), unit: unit,
            date: "Today",
            rangeLabel: baseline.map { WhoopFormat.oneDecimal($0) + " " + unit },
            series: series, labels: ["Typical", "", "Today"],
            rangeLow: baseline != nil ? bandLow : nil,
            rangeHigh: baseline != nil ? bandHigh : nil,
            color: color,
            statStripItems: stats,
            onClose: { openVital = nil }
        )
    }

    private func trend(_ d: DeltaDirection?) -> MetricCard.Trend {
        switch d {
        case .up: return .up
        case .down: return .down
        default: return .none
        }
    }

    private func tone(_ d: DeltaDirection?, lowerIsBetter: Bool) -> Color {
        switch d {
        case .up: return lowerIsBetter ? Theme.Chart.calories : Theme.Colors.tint
        case .down: return lowerIsBetter ? Theme.Colors.tint : Theme.Chart.calories
        default: return Theme.Colors.labelSecondary
        }
    }
}

private struct StressTeaseCard: View {
    let stress: StressDetail?
    let day: String

    private var hasGraph: Bool { (stress?.graph.isEmpty == false) }

    var body: some View {
        if hasGraph, let stress {
            NavigationLink(value: WhoopRoute.stress(day: day)) {
                card(stress)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open stress detail")
        } else {
            calibratingCard
        }
    }

    private func card(_ stress: StressDetail) -> some View {
        let level = stress.currentStress
        let values = stress.graph.map(\.value)

        return Card(metricAccent: Theme.Chart.calories) {
            HStack {
                WhoopSectionTitle(icon: "thermometer.medium", title: "Stress", color: Theme.Chart.calories)
                Spacer(minLength: 0)
                InfoDisclosure(
                    title: "Stress",
                    body: "Whoop's stress monitor runs on a 0 to 3 scale through the day. This is your own reading, shown as a number and a color, nothing more."
                )
                Image(systemName: "chevron.forward")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Colors.tint)
            }

            HStack(alignment: .center) {
                MetricCard(
                    icon: "waveform.path.ecg",
                    title: WhoopColor.stressBandLabel(level, state: stress.stressState),
                    value: level.map { WhoopFormat.oneDecimal($0) } ?? "–",
                    unit: "/ \(Int(WhoopScreen.stressMax))",
                    accent: WhoopColor.stress(level, state: stress.stressState)
                )
                .frame(maxWidth: 180)
                Spacer(minLength: Theme.Spacing.md)
                if values.count > 1 {
                    Sparkline(values: values, color: Theme.Chart.calories, width: 120, height: 56)
                }
            }
        }
    }

    private var calibratingCard: some View {
        Card(metricAccent: Theme.Chart.calories) {
            WhoopSectionTitle(icon: "thermometer.medium", title: "Stress", color: Theme.Chart.calories)
            Txt(stress?.stressState == "CALIBRATING"
                ? "Whoop's stress monitor is still calibrating for this day."
                : "No stress data for this day yet.",
                variant: .footnote, color: .labelTertiary)
        }
    }
}

private struct SleepCard: View {
    let summary: WhoopSummary
    var need: WhoopSleepNeed?
    let day: String

    private var hasSummary: Bool { summary.sleepHours != nil || summary.sleepPerformancePct != nil }

    private static let previewStages = [1, 2, 3, 3, 2, 1, 0, 3, 2, 1, 2, 3]

    var body: some View {
        NavigationLink(value: WhoopRoute.sleep(day: day)) {
            Card(metricAccent: Theme.Chart.sleep) {
                HStack {
                    WhoopSectionTitle(icon: "moon.fill", title: "Sleep", color: Theme.Chart.sleep)
                    Spacer(minLength: 0)
                    HStack(spacing: Theme.Spacing.xs / 2) {
                        Txt("Stages", variant: .footnote, color: .tint)
                        Image(systemName: "chevron.forward")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Colors.tint)
                    }
                }

                if hasSummary {
                    SleepStagesChart(
                        stages: Self.previewStages,
                        colors: [Theme.Colors.labelTertiary, Theme.Chart.recovery, Theme.Chart.fat, Theme.Chart.sleep],
                        width: WhoopChart.cardWidth, height: 56
                    )
                    HStack(spacing: Theme.Spacing.xl) {
                        WhoopStat(label: "Time asleep",
                                  value: summary.sleepHours.map { WhoopFormat.hoursMinutes($0) } ?? "–",
                                  accent: Theme.Chart.sleep)
                        WhoopStat(label: "Performance",
                                  value: summary.sleepPerformancePct.map { "\(Int($0.rounded()))%" } ?? "–")
                        if let rec = need?.recommendedMinutes {
                            WhoopStat(label: "Whoop suggests", value: WhoopFormat.minutesHm(rec))
                        }
                    }
                    if let need, day == DateStrip.toKey(Date()) {
                        SleepNeedBreakdown(need: need)
                    }
                } else {
                    Txt("No sleep recorded for this day yet.", variant: .footnote, color: .labelTertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open sleep detail")
    }
}

/// The components of Whoop's sleep need (baseline + debt + strain − nap credit), each restated as a
/// chip. Shows only the parts Whoop reported; purely descriptive.
private struct SleepNeedBreakdown: View {
    let need: WhoopSleepNeed

    private var parts: [(String, Int)] {
        var out: [(String, Int)] = []
        if let b = need.baselineMinutes { out.append(("Baseline", b)) }
        if let d = need.debtMinutes, d > 0 { out.append(("Sleep debt", d)) }
        if let s = need.strainMinutes, s > 0 { out.append(("From strain", s)) }
        if let n = need.napCreditMinutes, n > 0 { out.append(("Nap credit", -n)) }
        return out
    }

    var body: some View {
        if !parts.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(parts, id: \.0) { label, mins in
                    HStack {
                        Txt(label, variant: .footnote, color: .labelSecondary)
                        Spacer(minLength: 0)
                        Txt((mins < 0 ? "−" : "+") + WhoopFormat.minutesHm(abs(mins)),
                            variant: .footnote)
                    }
                }
            }
            .padding(.top, Theme.Spacing.xs)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Sleep need breakdown")
        }
    }
}

private struct HeartRateCard: View {
    let summary: WhoopSummary
    let strain: StrainDetail?
    /// The night's per-minute HR curve (Whoop's overnight recording, the only HR-over-time the mobile
    /// API exposes). Empty → the card keeps its zones-only layout.
    var hrCurve: [SleepHrPoint] = []
    /// The current strap HR (LIVE_HR tile), polled while the tab is open. nil → no live row.
    var live: WhoopLiveHr?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        let zone13 = strain?.zone13Ms ?? 0
        let zone45 = strain?.zone45Ms ?? 0
        let hasZones = zone13 > 0 || zone45 > 0
        let maxMs = Swift.max(zone13, zone45, 1)

        Card(metricAccent: Theme.Chart.heartrate) {
            HStack {
                WhoopSectionTitle(icon: "heart.fill", title: "Heart rate", color: Theme.Chart.heartrate)
                Spacer(minLength: 0)
                InfoDisclosure(
                    title: "Heart rate",
                    body: "Your live strap heart rate when it's streaming, your overnight per-minute curve, your resting rate, and time in zones. Whoop's app doesn't expose an all-day curve, so the continuous trace is the night's."
                )
            }

            if let live, let bpm = live.bpm, live.isRecording {
                HStack(spacing: Theme.Spacing.sm) {
                    Circle().fill(Theme.Chart.heartrate)
                        .frame(width: 8, height: 8)
                        .opacity(reduceMotion ? 1 : (pulse ? 0.3 : 1))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
                    Text("\(bpm)")
                        .font(Theme.Font.statNumber)
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .foregroundStyle(Theme.Colors.label)
                    Txt("bpm now", variant: .subhead, color: .labelSecondary)
                }
                .onAppear { pulse = true }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Live heart rate \(bpm) beats per minute")
            }

            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Text(summary.rhrBpm.map { String(Int($0.rounded())) } ?? "–")
                    .font(Theme.Font.statNumber)
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .foregroundStyle(Theme.Colors.label)
                Txt("bpm resting", variant: .subhead, color: .labelSecondary)
            }

            if hrCurve.count > 1 {
                let sorted = hrCurve.sorted { $0.x < $1.x }
                Txt("Overnight", variant: .footnote, color: .labelTertiary)
                SleepHrCurve(
                    points: hrCurve,
                    startLabel: sorted.first?.clock ?? "",
                    endLabel: sorted.last?.clock ?? "",
                    height: 150,
                    width: WhoopChart.cardWidth
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "Overnight heart rate: \(hrCurve.count) samples, low \(Int(hrCurve.map(\.bpm).min() ?? 0)), high \(Int(hrCurve.map(\.bpm).max() ?? 0)) beats per minute"
                )
            }

            if hasZones {
                VStack(spacing: Theme.Spacing.md) {
                    ZoneRow(label: "Zones 1–3", value: WhoopFormat.ms(zone13),
                            fraction: zone13 / maxMs, color: Theme.Chart.activity)
                    ZoneRow(label: "Zones 4–5", value: WhoopFormat.ms(zone45),
                            fraction: zone45 / maxMs, color: Theme.Chart.heartrate)
                }
            } else {
                Txt("No heart-rate zone time logged for this day yet.",
                    variant: .footnote, color: .labelTertiary)
            }
        }
    }
}

/// Surfaces Whoop's computed behavior impacts ("Alcohol · −12%") verbatim. Descriptive only: the
/// association Whoop found, never a diagnosis or instruction. Behaviors with too little data show
/// "Not enough data yet" rather than a false +/−.
private struct BehaviorImpactCard: View {
    let impacts: [WhoopBehaviorImpact]

    var body: some View {
        if !impacts.isEmpty {
            Card(metricAccent: Theme.Chart.recovery) {
                HStack {
                    WhoopSectionTitle(icon: "sparkles", title: "Behavior impact", color: Theme.Chart.recovery)
                    Spacer(minLength: 0)
                    InfoDisclosure(
                        title: "Behavior impact",
                        body: "How your logged behaviors line up with your recovery, as Whoop measured it over time. These are associations from your own data. Not advice, and not a cause."
                    )
                }
                VStack(spacing: Theme.Spacing.md) {
                    ForEach(impacts) { impact in
                        BehaviorImpactRow(impact: impact)
                    }
                }
            }
        }
    }
}

private struct BehaviorImpactRow: View {
    let impact: WhoopBehaviorImpact

    private var tint: Color {
        switch impact.direction {
        case .positive: return Theme.Chart.recovery
        case .negative: return Theme.Colors.danger
        case .insufficient: return Theme.Colors.labelTertiary
        }
    }

    var body: some View {
        HStack {
            Txt(impact.name, variant: .body)
            Spacer(minLength: Theme.Spacing.sm)
            if let display = impact.impactDisplay {
                Text(display)
                    .font(Theme.Font.bodyEmphasized)
                    .monospacedDigit()
                    .foregroundStyle(tint)
            } else {
                Txt("Not enough data yet", variant: .footnote, color: .labelTertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            impact.impactDisplay.map { "\(impact.name): \($0) recovery" }
                ?? "\(impact.name): not enough data yet"
        )
    }
}

/// One HR-zone row: a label + minutes header over a progress bar filled to its share of the busiest
/// band in its zone tint. Restates the user's own zone minutes; never classifies.
private struct ZoneRow: View {
    let label: String
    let value: String
    let fraction: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                HStack(spacing: Theme.Spacing.sm) {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Txt(label, variant: .footnote, color: .labelSecondary)
                }
                Spacer(minLength: 0)
                Txt(value, variant: .footnote)
            }
            ProgressBar(progress: min(1, max(0, fraction)), color: color, height: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}

/// Shared responsive chart width: the screen width minus the screen and card horizontal padding, so
/// Canvas charts fill the card without clipping.
enum WhoopChart {
    static var cardWidth: CGFloat {
        let horizontal = Theme.Spacing.xl * 2 + Theme.Spacing.lg * 2
        return Swift.max(220, screenWidth - horizontal)
    }

    /// The active window scene's width. Reads the foreground-active `UIWindowScene` instead of the
    /// deprecated `UIScreen.main`, falling back to the reference iPhone width when no scene is
    /// connected yet (very early in launch).
    private static var screenWidth: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .screen.bounds.width ?? 393
    }
}

#if DEBUG
#Preview("Whoop (populated)") {
    WhoopScreen()
        .environment(AppModel.sample)
}
#endif
