import SwiftUI

struct RecoveryDetailScreen: View {
    @Environment(AppModel.self) private var appModel

    /// The day to show (YYYY-MM-DD, local).
    let date: String

    private enum Phase: Equatable { case loading, ready, empty, notLinked }

    @State private var phase: Phase = .loading
    @State private var summary: WhoopSummary?
    /// Recovery % history for the scrubbable trend chart (oldest → newest).
    @State private var history: [WhoopHistoryPoint] = []
    /// ~18 weeks of daily recovery % for the calendar heatmap, oldest → newest.
    @State private var calendar: [Double] = []
    @State private var refreshing = false
    @State private var showHrvDetail = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                switch phase {
                case .notLinked:
                    ConnectWhoopState(
                        title: "Connect Whoop in Settings",
                        message: "Link your Whoop account to see your recovery, the vitals behind it, and what tends to move with it here."
                    )
                case .loading:
                    SkeletonCard()
                case .empty:
                    WhoopNoDataState(
                        title: "No recovery data for this day",
                        message: "Once your Whoop has synced this day it'll show up here. Pull down or tap below to try again.",
                        refreshing: refreshing,
                        onRefresh: { Task { await refresh() } }
                    )
                case .ready:
                    if let summary {
                        content(summary)
                    }
                }
            }
            .padding(Theme.Spacing.xl)
            .padding(.bottom, 40)
        }
        .background(Theme.Colors.background)
        .scrollIndicators(.hidden)
        .navigationTitle("Recovery")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await refresh() }
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ summary: WhoopSummary) -> some View {
        RecoveryHeroCard(summary: summary, history: history)
        if !calendar.isEmpty {
            RecoveryCalendarCard(values: calendar)
        }
        RecoveryVitalsGrid(summary: summary, showHrvDetail: $showHrvDetail)
        WhatCorrelatesCard()
    }

    private func load() async {
        if appModel.usesSampleData {
            summary = SampleData.whoopSummary
            history = SampleData.recoveryTrend
            calendar = SampleData.recoveryCalendar
            phase = summary?.recoveryPct == nil ? .empty : .ready
            return
        }
        guard await appModel.whoop.isLinked() else {
            phase = .notLinked
            return
        }
        phase = .loading
        await fetch(force: false)
    }

    private func refresh() async {
        if appModel.usesSampleData { return }
        guard await appModel.whoop.isLinked() else {
            phase = .notLinked
            return
        }
        refreshing = true
        await fetch(force: true)
        refreshing = false
    }

    private func fetch(force: Bool) async {
        let next = await appModel.whoop.summary(date: date, force: force)
        let points = await appModel.whoop.history(metric: .recovery, days: 14)
        let cal = await appModel.whoop.history(metric: .recovery, days: 126)
        summary = next
        history = points
        calendar = cal.compactMap { $0.value }
        phase = (next?.recoveryPct == nil) ? .empty : .ready
    }
}

private struct RecoveryHeroCard: View {
    let summary: WhoopSummary
    let history: [WhoopHistoryPoint]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pct = summary.recoveryPct ?? 0
        let real = history.compactMap { p -> (date: String, value: Double)? in p.value.map { (p.date, $0) } }
        let values = real.map(\.value)

        Card(metricAccent: Theme.Chart.recovery) {
            HStack {
                Txt("RECOVERY", variant: .sectionHeader, color: .labelSecondary)
                Spacer(minLength: 0)
                Txt(asOf, variant: .footnote, color: .labelTertiary)
            }

            HStack {
                Spacer(minLength: 0)
                GradientRing(
                    progress: pct / 100,
                    title: summary.recoveryPct.map { "\(Int($0.rounded()))%" } ?? "–",
                    caption: "recovered",
                    gradient: Theme.Chart.gradientStops(for: Theme.Chart.recovery),
                    track: Theme.Chart.ringTrack(for: Theme.Chart.recovery),
                    lineWidth: 16,
                    size: 168,
                    animated: !reduceMotion
                )
                Spacer(minLength: 0)
            }

            if values.count >= 2 {
                let labels = real.enumerated().map { i, p in
                    (i == 0 || i == real.count - 1) ? tickLabel(p.date) : ""
                }
                Txt("Recovery, last \(values.count) days", variant: .footnote, color: .labelTertiary)
                InteractiveLineChart(
                    values: values, labels: labels,
                    color: Theme.Chart.recovery,
                    width: WhoopChart.cardWidth, height: 160,
                    format: { "\(Int($0.rounded()))%" }
                )
            }
        }
    }

    private var asOf: String {
        let label = WhoopFormat.asOfLabel(summary.recordedAt, summary.updatedAt)
        return label.isEmpty ? "" : label.prefix(1).uppercased() + label.dropFirst()
    }

    private static let weekday = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private func tickLabel(_ dayKey: String) -> String {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return dayKey }
        var c = DateComponents()
        c.year = parts[0]; c.month = parts[1]; c.day = parts[2]
        guard let date = Calendar.current.date(from: c) else { return dayKey }
        let weekday = Calendar.current.component(.weekday, from: date) - 1
        return Self.weekday[weekday]
    }
}

private struct RecoveryVitalsGrid: View {
    let summary: WhoopSummary
    @Binding var showHrvDetail: Bool

    private struct Vital: Identifiable {
        let id: String
        let icon: String
        let title: String
        let value: String
        let unit: String?
        let trend: MetricCard.Trend
        let trendColor: Color
        let accent: Color
    }

    var body: some View {
        let vitals = buildVitals()
        let columns = [GridItem(.flexible(), spacing: Theme.Spacing.md),
                       GridItem(.flexible(), spacing: Theme.Spacing.md)]

        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            WhoopSectionTitle(icon: "heart.text.square.fill", title: "Vitals", color: Theme.Chart.heartrate)
            LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                ForEach(vitals) { v in
                    MetricCard(
                        icon: v.icon, title: v.title, value: v.value, unit: v.unit,
                        trend: v.trend, trendColor: v.trendColor,
                        status: "vs your typical", accent: v.accent
                    )
                }
            }
        }
    }

    private func buildVitals() -> [Vital] {
        let hrvDelta = WhoopFormat.delta(summary.hrvMs, summary.hrvBaselineMs, unit: "ms")
        let rhrDelta = WhoopFormat.delta(summary.rhrBpm, summary.rhrBaselineBpm, unit: "bpm")

        var vitals: [Vital] = []
        if let hrv = summary.hrvMs {
            vitals.append(Vital(
                id: "hrv", icon: "waveform.path.ecg", title: "HRV",
                value: WhoopFormat.oneDecimal(hrv), unit: "ms",
                trend: trend(hrvDelta?.direction), trendColor: trendColor(hrvDelta?.direction, lowerIsBetter: false),
                accent: Theme.Chart.recovery
            ))
        }
        if let rhr = summary.rhrBpm {
            vitals.append(Vital(
                id: "rhr", icon: "heart.fill", title: "Resting HR",
                value: String(Int(rhr.rounded())), unit: "bpm",
                trend: trend(rhrDelta?.direction), trendColor: trendColor(rhrDelta?.direction, lowerIsBetter: true),
                accent: Theme.Chart.heartrate
            ))
        }
        if let rr = summary.respiratoryRate {
            vitals.append(Vital(
                id: "rr", icon: "lungs.fill", title: "Respiratory",
                value: WhoopFormat.oneDecimal(rr), unit: "rpm",
                trend: .none, trendColor: Theme.Colors.labelSecondary, accent: Theme.Chart.recovery
            ))
        }
        if let spo2 = summary.spo2Pct {
            vitals.append(Vital(
                id: "spo2", icon: "drop.fill", title: "Blood oxygen",
                value: "\(Int(spo2.rounded()))", unit: "%",
                trend: .none, trendColor: Theme.Colors.labelSecondary, accent: Theme.Chart.strain
            ))
        }
        if let temp = summary.skinTempC {
            vitals.append(Vital(
                id: "temp", icon: "thermometer.medium", title: "Skin temp",
                value: WhoopFormat.oneDecimal(temp), unit: "°C",
                trend: .none, trendColor: Theme.Colors.labelSecondary, accent: Theme.Chart.calories
            ))
        }
        return vitals
    }

    private func trend(_ d: DeltaDirection?) -> MetricCard.Trend {
        switch d {
        case .up: return .up
        case .down: return .down
        default: return .none
        }
    }

    private func trendColor(_ d: DeltaDirection?, lowerIsBetter: Bool) -> Color {
        switch d {
        case .up: return lowerIsBetter ? Theme.Chart.calories : Theme.Colors.tint
        case .down: return lowerIsBetter ? Theme.Colors.tint : Theme.Chart.calories
        default: return Theme.Colors.labelSecondary
        }
    }
}

private struct WhatCorrelatesCard: View {
    private struct Driver: Identifiable {
        let id: String
        let icon: String
        let label: String
        let color: Color
    }

    private static let drivers: [Driver] = [
        .init(id: "sleep", icon: "moon.fill", label: "Sleep performance", color: Theme.Chart.sleep),
        .init(id: "strain", icon: "bolt.fill", label: "Day strain", color: Theme.Chart.strain),
        .init(id: "rhr", icon: "heart.fill", label: "Resting heart rate", color: Theme.Chart.heartrate),
    ]

    var body: some View {
        Card {
            HStack {
                WhoopSectionTitle(icon: "arrow.triangle.branch", title: "What moves with it", color: Theme.Chart.recovery)
                Spacer(minLength: 0)
                InfoDisclosure(
                    title: "What moves with it",
                    body: "These are the inputs that tend to track alongside your own recovery from day to day. It's a description of your patterns, not a cause."
                )
            }
            Txt("Days your recovery runs higher than usual tend to line up with these on your own record.",
                variant: .footnote, color: .labelSecondary)
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(Self.drivers) { d in
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: d.icon)
                            .font(.system(size: 14))
                            .foregroundStyle(d.color)
                            .frame(width: 22)
                        Txt(d.label, variant: .subhead, color: .labelSecondary)
                        Spacer(minLength: 0)
                        Image(systemName: "circle.dotted")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Colors.labelTertiary)
                    }
                }
            }
            Txt("Tracks more of your days to surface here.", variant: .footnote, color: .labelTertiary)
        }
    }
}

#if DEBUG
#Preview("Recovery detail (populated)") {
    NavigationStack {
        RecoveryDetailScreen(date: "2026-06-06")
    }
    .environment(AppModel.sample)
}
#endif
