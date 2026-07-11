import SwiftUI

struct ExploreScreen: View {
    @Environment(AppModel.self) private var appModel
    @State private var open: ExploreMetric?

    @State private var groups: [ExploreGroup] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                if groups.isEmpty {
                    SkeletonCard()
                    SkeletonCard(lines: 2)
                } else {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            SectionCaption(title: group.title)
                            SettingsGroup {
                                ForEach(group.metrics) { metric in
                                    ExploreMetricRow(metric: metric) {
                                        if metric.hasData { open = metric }
                                    }
                                }
                            }
                        }
                    }
                    footnote
                }
            }
            .padding(Theme.Spacing.xl)
            .padding(.bottom, 80)
        }
        .background(Theme.Colors.background)
        .scrollIndicators(.hidden)
        .navigationTitle("Explore")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $open) { metric in
            metric.detailSheet { open = nil }
                .presentationDetents([.large])
                .presentationCornerRadius(28)
        }
        .task { await load() }
    }

    /// Source the catalog. `.task` re-fires on every tab return, so this revalidates silently against
    /// the per-day cache; skeletons only show before the first resolve, never blanking rendered rows.
    private func load() async {
        if appModel.usesSampleData {
            groups = ExploreCatalog.groups
        } else {
            groups = await ExploreCatalog.liveGroups(whoop: appModel.whoop)
        }
    }

    private var header: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                WhoopSectionTitle(icon: "square.grid.2x2", title: "Browse every metric",
                                  color: Theme.Chart.recovery)
                Spacer(minLength: 0)
                InfoDisclosure(
                    title: "Your full data surface",
                    body: "Every Whoop signal Gains stores, grouped by category. Tap any metric to see its full history, your own typical range, and its high, low, and average over the window. These describe your own numbers, nothing more."
                )
            }
            Txt("Every signal Gains keeps, in one place. Tap a metric to open its history.",
                variant: .footnote, color: .labelSecondary)
        }
    }

    private var footnote: some View {
        Txt("Each row shows your latest reading and a mini trend. The full chart and your typical range are one tap away.",
            variant: .footnote, color: .labelTertiary)
    }
}

/// A single metric row. A metric with data is a pressable Button that opens its detail sheet; a
/// no-data metric renders flat (no value, sparkline, chevron, or tap).
private struct ExploreMetricRow: View {
    let metric: ExploreMetric
    let onTap: () -> Void

    var body: some View {
        if metric.hasData {
            Button(action: onTap) { content }
                .buttonStyle(PressableRowStyle())
                .accessibilityLabel(accessibilityText)
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(metric.name), no recent data")
        }
    }

    private var content: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: metric.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(metric.color)
                .frame(width: 30, height: 30)
                .background(Circle().fill(metric.color.opacity(0.14)))

            VStack(alignment: .leading, spacing: 2) {
                Text(metric.name)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Colors.label)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                if !metric.hasData {
                    Txt("No recent data", variant: .footnote, color: .labelTertiary)
                }
            }

            Spacer(minLength: Theme.Spacing.sm)

            if metric.hasData {
                if metric.series.count > 1 {
                    Sparkline(values: metric.series, color: metric.color, width: 52, height: 30)
                }
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(metric.latestValue)
                        .font(Theme.Font.statNumber)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Colors.label)
                    Text(metric.unit)
                        .font(Theme.Font.footnote)
                        .foregroundStyle(Theme.Colors.labelTertiary)
                }
                Image(systemName: "chevron.forward")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.labelTertiary)
            }
        }
        .padding(.vertical, Theme.Spacing.md + 2)
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var accessibilityText: String {
        "\(metric.name), \(metric.latestValue) \(metric.unit)"
    }
}

/// One browsable metric: display identity (name, glyph, hue, unit) plus the data to draw the row and its
/// detail sheet. An empty `series` means the signal isn't stored yet (`hasData == false`) and the row
/// degrades gracefully.
struct ExploreMetric: Identifiable {
    let id: String
    let name: String
    let icon: String
    let color: Color
    let unit: String
    /// The aligned daily history (oldest → newest). Empty = no stored series yet.
    let series: [Double]
    /// One-decimal vs whole-number formatting for the value + stats (HRV/strain are decimal; % / bpm aren't).
    let decimal: Bool

    var hasData: Bool { series.count > 1 }

    private var latest: Double? { series.last }

    /// The latest reading, formatted to the metric's precision (e.g. "94", "126", "17.9").
    var latestValue: String {
        guard let latest else { return "–" }
        return decimal ? Format.oneDecimal(latest) : Format.int(latest)
    }

    private func fmt(_ n: Double) -> String { decimal ? Format.oneDecimal(n) : Format.int(n) }

    /// Build this metric's detail sheet: its full series, a "vs your typical" band from the series
    /// min/max (the user's own range, never a clinical range), and an avg/min/max/latest stat strip.
    @ViewBuilder
    func detailSheet(onClose: @escaping () -> Void) -> some View {
        let lo = series.min() ?? 0
        let hi = series.max() ?? 0
        let avg = series.isEmpty ? 0 : series.reduce(0, +) / Double(series.count)
        let labels = (1...max(series.count, 1)).map { String($0) }

        MetricDetailSheet(
            title: name,
            value: latestValue,
            unit: unit,
            date: "Last \(series.count) days",
            rangeLabel: "\(fmt(lo)) - \(fmt(hi)) \(unit)",
            series: series,
            labels: labels,
            rangeLow: lo,
            rangeHigh: hi,
            color: color,
            statStripItems: [
                .init(label: "Avg", value: fmt(avg), unit: unit),
                .init(label: "Min", value: fmt(lo), unit: unit),
                .init(label: "Max", value: fmt(hi), unit: unit),
                .init(label: "Latest", value: latestValue, unit: unit),
            ],
            onClose: onClose
        )
    }
}

/// A named group of metrics (one section: header + grouped card).
struct ExploreGroup: Identifiable {
    let id: String
    let title: String
    let metrics: [ExploreMetric]
}

/// The catalog. One `build` defines every metric's identity (name, glyph, hue, unit, precision) so the
/// two sources can't disagree on the display: `groups` injects the seeded 21-day sample history for
/// previews; `liveGroups` injects the user's own cached Whoop history for real builds. Respiratory and
/// Stress have no cached series in either source, so they appear as "no recent data" rows.
enum ExploreCatalog {
    /// The sample-container catalog (previews/screenshots): the seeded 21-day sample history.
    static let groups: [ExploreGroup] = build(
        recovery: SampleData.recoveryHistory,
        hrv: SampleData.hrvHistory,
        rhr: SampleData.rhrHistory,
        sleepPerformance: SampleData.sleepPerformanceHistory,
        strain: SampleData.strainHistory
    )

    /// The real-build catalog: the same groups, each series read from the cached Whoop history the
    /// client already stores (only the user's own numbers). Sequential awaits on purpose: `history`
    /// serves at most 14 uncached days per call through the per-day cache, so long gaps backfill
    /// progressively across visits rather than fetching everything at once. Whoop history has no sleep-performance
    /// series, so its empty series renders the "no recent data" row instead of fabricating values.
    static func liveGroups(whoop: any WhoopService) async -> [ExploreGroup] {
        let days = SampleData.insightsDayCount
        let recovery = await whoop.history(metric: .recovery, days: days).compactMap(\.value)
        let hrv = await whoop.history(metric: .hrv, days: days).compactMap(\.value)
        let rhr = await whoop.history(metric: .rhr, days: days).compactMap(\.value)
        let strain = await whoop.history(metric: .strain, days: days).compactMap(\.value)
        return build(recovery: recovery, hrv: hrv, rhr: rhr, sleepPerformance: [], strain: strain)
    }

    private static func build(
        recovery: [Double], hrv: [Double], rhr: [Double],
        sleepPerformance: [Double], strain: [Double]
    ) -> [ExploreGroup] {
        [
            ExploreGroup(id: "recovery", title: "Recovery", metrics: [
                ExploreMetric(id: "recovery", name: "Recovery", icon: "arrow.clockwise.heart.fill",
                              color: Theme.Chart.recovery, unit: "%",
                              series: recovery, decimal: false),
                ExploreMetric(id: "hrv", name: "Heart rate variability", icon: "waveform.path.ecg",
                              color: Theme.Chart.recovery, unit: "ms",
                              series: hrv, decimal: true),
                ExploreMetric(id: "rhr", name: "Resting heart rate", icon: "heart.fill",
                              color: Theme.Chart.heartrate, unit: "bpm",
                              series: rhr, decimal: false),
                ExploreMetric(id: "respiratory", name: "Respiratory rate", icon: "lungs.fill",
                              color: Theme.Chart.recovery, unit: "rpm",
                              series: [], decimal: true),
            ]),
            ExploreGroup(id: "sleep", title: "Sleep", metrics: [
                ExploreMetric(id: "sleep-performance", name: "Sleep performance", icon: "moon.fill",
                              color: Theme.Chart.sleep, unit: "%",
                              series: sleepPerformance, decimal: false),
            ]),
            ExploreGroup(id: "strain", title: "Strain", metrics: [
                ExploreMetric(id: "strain", name: "Day strain", icon: "flame.fill",
                              color: Theme.Chart.strain, unit: "",
                              series: strain, decimal: true),
            ]),
            ExploreGroup(id: "stress", title: "Stress", metrics: [
                ExploreMetric(id: "stress", name: "Stress", icon: "thermometer.medium",
                              color: Theme.Chart.calories, unit: "",
                              series: [], decimal: true),
            ]),
        ]
    }
}

#if DEBUG
#Preview("Explore · catalog") {
    NavigationStack {
        ExploreScreen()
            .environment(AppModel.sample)
    }
}
#endif
