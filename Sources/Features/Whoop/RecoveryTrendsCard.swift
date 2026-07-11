import SwiftUI

struct RecoveryTrendsCard: View {
    @Environment(AppModel.self) private var appModel

    private enum LoadState: Equatable { case loading, ready, empty }
    /// The three view modes: two ranges + the recovery heatmap.
    private enum Mode: Int, CaseIterable { case week = 0, twoWeeks = 1, heatmap = 2 }

    @State private var mode: Mode = .week
    @State private var state: LoadState = .loading
    @State private var series: [WhoopHistoryMetric: [WhoopHistoryPoint]] = [:]
    /// The metric whose detail sheet is open (nil = none).
    @State private var openMetric: WhoopHistoryMetric?

    /// The three series the Whoop trend tab shows, each with its label, unit, and hue.
    private static let metrics: [(metric: WhoopHistoryMetric, label: String, unit: String, color: Color)] = [
        (.recovery, "Recovery", "%", Theme.Chart.recovery),
        (.hrv, "HRV", "ms", Theme.Chart.heartrate),
        (.rhr, "Resting HR", "bpm", Theme.Chart.heartrate),
    ]

    /// Days of history the current mode needs.
    private var rangeDays: Int {
        switch mode {
        case .week: return 7
        case .twoWeeks: return 14
        case .heatmap: return 14
        }
    }

    var body: some View {
        Card {
            WhoopSectionTitle(icon: "chart.line.uptrend.xyaxis", title: "Trends")

            SegmentedPills(options: ["7 days", "14 days", "Heatmap"], selection: modeBinding)

            switch state {
            case .loading:
                Txt("Loading your last \(rangeDays) days…", variant: .footnote, color: .labelTertiary)
            case .empty:
                Txt("Your HRV, resting heart rate, and recovery trends build up here as Whoop syncs more days.",
                    variant: .footnote, color: .labelTertiary)
            case .ready:
                if mode == .heatmap {
                    heatmap
                } else {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                        ForEach(Self.metrics, id: \.metric) { entry in
                            TrendRow(
                                label: entry.label, unit: entry.unit, color: entry.color,
                                points: series[entry.metric] ?? [],
                                onTap: { openMetric = entry.metric }
                            )
                        }
                    }
                }
            }
        }
        .task(id: rangeDays) { await load() }
        .sheet(item: $openMetric) { metric in
            detailSheet(for: metric)
                .presentationDetents([.large])
                .presentationCornerRadius(28)
        }
    }

    private var modeBinding: Binding<Int> {
        Binding(get: { mode.rawValue }, set: { mode = Mode(rawValue: $0) ?? .week })
    }

    private var heatmap: some View {
        let days = (series[.recovery] ?? []).map { RecoveryHeatmap.Day(date: $0.date, pct: $0.value) }
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if days.isEmpty {
                Txt("Recovery days fill in here as Whoop syncs more of them.",
                    variant: .footnote, color: .labelTertiary)
            } else {
                RecoveryHeatmap(days: days, onTapDay: { _ in })
                Txt("Each square is a day, shaded by your recovery.", variant: .footnote, color: .labelTertiary)
            }
        }
    }

    @ViewBuilder
    private func detailSheet(for metric: WhoopHistoryMetric) -> some View {
        let entry = Self.metrics.first { $0.metric == metric }
        let points = (series[metric] ?? []).compactMap { p -> (date: String, value: Double)? in
            p.value.map { (p.date, $0) }
        }
        let values = points.map(\.value)
        let labels = points.map { tickLabel($0.date) }
        let unit = entry?.unit ?? ""
        let color = entry?.color ?? Theme.Chart.recovery
        let avg = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)

        MetricDetailSheet(
            title: entry?.label ?? "Trend",
            value: values.last.map { WhoopFormat.oneDecimal($0) } ?? "–",
            unit: unit,
            date: "Last \(values.count) days",
            series: values,
            labels: labels,
            color: color,
            statStripItems: [
                .init(label: "Avg", value: avg.map { WhoopFormat.oneDecimal($0) } ?? "–", unit: unit),
                .init(label: "Min", value: values.min().map { WhoopFormat.oneDecimal($0) } ?? "–", unit: unit),
                .init(label: "Max", value: values.max().map { WhoopFormat.oneDecimal($0) } ?? "–", unit: unit),
                .init(label: "Latest", value: values.last.map { WhoopFormat.oneDecimal($0) } ?? "–", unit: unit),
            ],
            onClose: { openMetric = nil }
        )
    }

    private func load() async {
        if series.isEmpty { state = .loading }
        let days = rangeDays
        var next: [WhoopHistoryMetric: [WhoopHistoryPoint]] = [:]
        if appModel.usesSampleData {
            next[.recovery] = sample(SampleData.recoveryTrend, days: days)
            next[.hrv] = sample(SampleData.hrvTrend, days: days)
            next[.rhr] = sample(SampleData.rhrTrend, days: days)
        } else {
            next[.recovery] = await appModel.whoop.history(metric: .recovery, days: days)
            next[.hrv] = await appModel.whoop.history(metric: .hrv, days: days)
            next[.rhr] = await appModel.whoop.history(metric: .rhr, days: days)
        }
        series = next
        let anyDrawable = Self.metrics.contains { (next[$0.metric] ?? []).filter { $0.value != nil }.count >= 2 }
        state = anyDrawable ? .ready : .empty
    }

    /// Trim the seeded sample series to the requested window. The sample only carries a week, so the
    /// 14-day range just shows the same span.
    private func sample(_ points: [WhoopHistoryPoint], days: Int) -> [WhoopHistoryPoint] {
        Array(points.suffix(min(days, points.count)))
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

extension WhoopHistoryMetric: Identifiable {
    public var id: String { rawValue }
}

private struct TrendRow: View {
    let label: String
    let unit: String
    let color: Color
    let points: [WhoopHistoryPoint]
    var onTap: () -> Void

    private static let weekday = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        let real = points.compactMap { p -> (date: String, value: Double)? in
            p.value.map { (p.date, $0) }
        }
        let values = real.map(\.value)
        let latest = real.last?.value

        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: Theme.Spacing.xs) {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Txt(label, variant: .bodyEmphasized)
                }
                Spacer(minLength: 0)
                if let latest {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(WhoopFormat.oneDecimal(latest))
                            .font(Theme.Font.statNumber)
                            .monospacedDigit()
                            .foregroundStyle(color)
                        Text(unit)
                            .font(Theme.Font.footnote)
                            .foregroundStyle(Theme.Colors.labelTertiary)
                    }
                } else {
                    Txt("no data", variant: .footnote, color: .labelSecondary)
                }
            }
            if values.count >= 2 {
                let labels = real.enumerated().map { i, p in
                    (i == 0 || i == real.count - 1) ? tickLabel(p.date) : ""
                }
                Button(action: onTap) {
                    TrendChart(points: values, color: color, height: 88,
                               width: WhoopChart.cardWidth, labels: labels)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(label) detail")
            } else {
                Txt("Not enough days yet to chart \(label).", variant: .footnote, color: .labelTertiary)
            }
        }
    }

    /// "Mon" short weekday tick from a YYYY-MM-DD key.
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
