import SwiftUI

struct StressDetailScreen: View {
    @Environment(AppModel.self) private var appModel

    /// The day to show (YYYY-MM-DD, local).
    let date: String

    private enum Phase: Equatable { case loading, ready, empty, notLinked }

    @State private var phase: Phase = .loading
    @State private var detail: StressDetail?
    @State private var refreshing = false

    private static let stressMax: Double = 3
    private static let elevatedLevel: Double = 1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                switch phase {
                case .notLinked:
                    ConnectWhoopState(
                        title: "Connect Whoop in Settings",
                        message: "Link your Whoop account to see your day-long stress monitor, sessions, and trends here."
                    )
                case .loading:
                    SkeletonCard()
                case .empty:
                    WhoopNoDataState(
                        title: "No stress data for this day",
                        message: detail?.stressState == "CALIBRATING"
                            ? "Whoop's stress monitor is still calibrating. Pull down or tap below to try again."
                            : "Once your Whoop has synced this day it'll show up here. Pull down or tap below to try again.",
                        refreshing: refreshing,
                        onRefresh: { Task { await refresh() } }
                    )
                case .ready:
                    if let detail {
                        StressGraphCard(detail: detail, stressMax: Self.stressMax)
                        StressStatsCard(detail: detail, stressMax: Self.stressMax)
                        StressSessionsCard(detail: detail, elevatedLevel: Self.elevatedLevel)
                    }
                }
            }
            .padding(Theme.Spacing.xl)
            .padding(.bottom, 40)
        }
        .background(Theme.Colors.background)
        .scrollIndicators(.hidden)
        .navigationTitle("Stress")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await refresh() }
        .task { await load() }
    }

    private func load() async {
        if appModel.usesSampleData {
            detail = SampleData.stressDetail
            phase = SampleData.stressDetail.graph.isEmpty ? .empty : .ready
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
        let next = await appModel.whoop.stressDetail(date: date, force: force)
        detail = next
        phase = (next != nil && next?.graph.isEmpty == false) ? .ready : .empty
    }
}

private struct StressGraphCard: View {
    let detail: StressDetail
    let stressMax: Double

    var body: some View {
        let level = detail.currentStress
        let tint = WhoopColor.stress(level, state: detail.stressState)
        let values = detail.graph.map(\.value)
        let labels = detail.graph.enumerated().map { i, p in
            (i == 0 || i == detail.graph.count - 1 || i == detail.graph.count / 2) ? p.time : ""
        }

        Card(metricAccent: Theme.Chart.calories) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(level.map { WhoopFormat.oneDecimal($0) } ?? "–")
                            .font(Theme.Font.heroNumber)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(Theme.Colors.label)
                        Txt("/ \(Int(stressMax))", variant: .bodyEmphasized, color: .labelTertiary)
                    }
                    HStack(spacing: Theme.Spacing.xs) {
                        Circle().fill(tint).frame(width: 8, height: 8)
                        Txt(WhoopColor.stressBandLabel(level, state: detail.stressState),
                            variant: .footnote, color: .labelSecondary)
                    }
                }
                Spacer(minLength: 0)
                if let trend = trendChip {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("vs your typical")
                            .font(Theme.Font.subhead.weight(.medium))
                            .foregroundStyle(Theme.Chart.calories)
                        Text(trend)
                            .font(Theme.Font.footnote)
                            .foregroundStyle(Theme.Colors.labelSecondary)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Capsule().fill(Theme.Chart.calories.opacity(0.10)))
                }
            }

            InteractiveLineChart(
                values: values, labels: labels,
                color: Theme.Chart.calories,
                width: WhoopChart.cardWidth, height: 180,
                format: { WhoopFormat.oneDecimal($0) }
            )
        }
    }

    /// A short "vs your typical" chip line from the day's trend word, or nil when none is present.
    private var trendChip: String? {
        let trend = WhoopFormat.titleCaseState(detail.trend)
        if !trend.isEmpty { return trend }
        if let raw = detail.trend, !raw.isEmpty { return raw }
        return nil
    }
}

private struct StressStatsCard: View {
    let detail: StressDetail
    let stressMax: Double

    var body: some View {
        let values = detail.graph.map(\.value)
        let avg = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        let items: [MetricStatStrip.Item] = [
            .init(label: "Avg", value: avg.map { WhoopFormat.oneDecimal($0) } ?? "–"),
            .init(label: "Min", value: detail.minStress.map { WhoopFormat.oneDecimal($0) } ?? "–"),
            .init(label: "Max", value: detail.maxStress.map { WhoopFormat.oneDecimal($0) } ?? "–"),
            .init(label: "Latest", value: detail.currentStress.map { WhoopFormat.oneDecimal($0) } ?? "–"),
        ]

        Card {
            WhoopSectionTitle(icon: "chart.bar.fill", title: "Day range", color: Theme.Chart.calories)
            MetricStatStrip(items: items)
            if let avg {
                BaselineDottedRow(
                    label: "Day average",
                    valueText: "\(WhoopFormat.oneDecimal(avg)) / \(Int(stressMax))",
                    color: Theme.Chart.calories
                )
            }
        }
    }
}

/// A dotted-line row: a short dashed rule + a label/value, marking the day's own average as a
/// reference. Descriptive only.
private struct BaselineDottedRow: View {
    let label: String
    let valueText: String
    let color: Color

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Line()
                .stroke(color.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: 28, height: 1)
            Txt(label, variant: .footnote, color: .labelSecondary)
            Spacer(minLength: 0)
            Text(valueText)
                .font(Theme.Font.footnote)
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.labelTertiary)
        }
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return p
        }
    }
}

private struct StressSessionsCard: View {
    let detail: StressDetail
    let elevatedLevel: Double

    var body: some View {
        let sessions = deriveSessions(detail.graph)
        Card {
            WhoopSectionTitle(icon: "clock.fill", title: "Elevated periods", color: Theme.Chart.calories)
            if sessions.isEmpty {
                Txt("No elevated-stress periods recorded for this day.",
                    variant: .footnote, color: .labelTertiary)
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(sessions) { session in
                        SessionBadge(session: session)
                    }
                }
            }
        }
    }

    /// Contiguous runs of the day curve at or above the "medium" threshold; each run carries its clock
    /// window and peak 0–3 level. A restatement of the curve, not a classification.
    private func deriveSessions(_ graph: [StressGraphPoint]) -> [StressSession] {
        var sessions: [StressSession] = []
        var current: StressSession?
        for point in graph {
            if point.value >= elevatedLevel {
                if var run = current {
                    run.end = point.time
                    run.peak = max(run.peak, point.value)
                    current = run
                } else {
                    current = StressSession(start: point.time, end: point.time, peak: point.value)
                }
            } else if let c = current {
                sessions.append(c)
                current = nil
            }
        }
        if let c = current { sessions.append(c) }
        return sessions
    }
}

/// A contiguous elevated-stress run: its clock window + peak 0–3 level.
private struct StressSession: Identifiable {
    var start: String
    var end: String
    var peak: Double
    var id: String { "\(start)-\(end)" }
}

/// One elevated period as a tinted badge capsule: the clock window on the left + a peak-level pill in
/// the stress hue on the right.
private struct SessionBadge: View {
    let session: StressSession

    var body: some View {
        let tint = WhoopColor.stress(session.peak)
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 12))
                .foregroundStyle(tint)
            Txt(session.start == session.end ? session.start : "\(session.start) – \(session.end)",
                variant: .subhead, color: .labelSecondary)
            Spacer(minLength: Theme.Spacing.sm)
            HStack(spacing: Theme.Spacing.xs) {
                Text("peak \(WhoopFormat.oneDecimal(session.peak))")
                    .font(Theme.Font.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                Txt(WhoopColor.stressBandLabel(session.peak), variant: .footnote, color: .labelTertiary)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Capsule().fill(tint.opacity(0.12)))
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(tint.opacity(0.06))
        )
    }
}

#if DEBUG
#Preview("Stress detail (populated)") {
    NavigationStack {
        StressDetailScreen(date: "2026-06-06")
    }
    .environment(AppModel.sample)
}
#endif
