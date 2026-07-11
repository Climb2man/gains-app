import SwiftUI

struct StrainDetailScreen: View {
    @Environment(AppModel.self) private var appModel

    /// The day to show (YYYY-MM-DD, local).
    let date: String

    private enum Phase: Equatable { case loading, ready, empty, notLinked }

    private static let strainMax: Double = 21

    @State private var phase: Phase = .loading
    @State private var detail: StrainDetail?
    /// The day summary: carries the one real daily energy figure (the strain endpoint has none).
    @State private var summary: WhoopSummary?
    /// Day-strain history for the scrubbable trend chart (oldest → newest).
    @State private var history: [WhoopHistoryPoint] = []
    @State private var refreshing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                switch phase {
                case .notLinked:
                    ConnectWhoopState(
                        title: "Connect Whoop in Settings",
                        message: "Link your Whoop account to see your day strain, heart-rate zones, and energy burned here."
                    )
                case .loading:
                    SkeletonCard()
                case .empty:
                    WhoopNoDataState(
                        title: "No strain data for this day",
                        message: "Once your Whoop has synced this day it'll show up here. Pull down or tap below to try again.",
                        refreshing: refreshing,
                        onRefresh: { Task { await refresh() } }
                    )
                case .ready:
                    if let detail {
                        StrainHeroCard(detail: detail, summary: summary, history: history, strainMax: Self.strainMax)
                        StrainZonesCard(detail: detail)
                    }
                }
            }
            .padding(Theme.Spacing.xl)
            .padding(.bottom, 40)
        }
        .background(Theme.Colors.background)
        .scrollIndicators(.hidden)
        .navigationTitle("Strain")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await refresh() }
        .task { await load() }
    }

    private func load() async {
        if appModel.usesSampleData {
            detail = SampleData.strainDetail
            summary = SampleData.whoopSummary
            history = SampleData.strainTrend
            phase = (SampleData.strainDetail.score == nil) ? .empty : .ready
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
        let next = await appModel.whoop.strainDetail(date: date)
        let sum = await appModel.whoop.summary(date: date, force: force)
        let points = await appModel.whoop.history(metric: .strain, days: 14)
        detail = next
        summary = sum
        history = points
        phase = (next?.score == nil) ? .empty : .ready
    }
}

private struct StrainHeroCard: View {
    let detail: StrainDetail
    let summary: WhoopSummary?
    let history: [WhoopHistoryPoint]
    let strainMax: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let score = detail.score ?? 0
        let real = history.compactMap { p -> (date: String, value: Double)? in p.value.map { (p.date, $0) } }
        let values = real.map(\.value)

        Card(metricAccent: Theme.Chart.strain) {
            Txt("DAY STRAIN", variant: .sectionHeader, color: .labelSecondary)

            HStack(alignment: .center, spacing: Theme.Spacing.lg) {
                GradientRing(
                    progress: min(1, max(0, score / strainMax)),
                    title: detail.score.map { WhoopFormat.oneDecimal($0) } ?? "–",
                    caption: "of \(Int(strainMax))",
                    gradient: Theme.Chart.gradientStops(for: Theme.Chart.strain),
                    track: Theme.Chart.ringTrack(for: Theme.Chart.strain),
                    lineWidth: 14,
                    size: 140,
                    animated: !reduceMotion
                )
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Txt("Energy burned", variant: .footnote, color: .labelSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(summary?.calories.map { Format.int($0) } ?? "–")
                            .font(Theme.Font.statNumber)
                            .monospacedDigit()
                            .contentTransition(reduceMotion ? .identity : .numericText())
                            .foregroundStyle(Theme.Colors.label)
                        Txt("kcal", variant: .footnote, color: .labelTertiary)
                    }
                    if detail.workoutsCount > 0 {
                        Txt("\(detail.workoutsCount) workout\(detail.workoutsCount == 1 ? "" : "s") today",
                            variant: .footnote, color: .labelTertiary)
                    }
                }
                Spacer(minLength: 0)
            }

            if values.count >= 2 {
                let labels = real.enumerated().map { i, p in
                    (i == 0 || i == real.count - 1) ? tickLabel(p.date) : ""
                }
                Txt("Strain, last \(values.count) days", variant: .footnote, color: .labelTertiary)
                InteractiveLineChart(
                    values: values, labels: labels,
                    color: Theme.Chart.strain,
                    width: WhoopChart.cardWidth, height: 160,
                    format: { WhoopFormat.oneDecimal($0) }
                )
            }
        }
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

private struct StrainZonesCard: View {
    let detail: StrainDetail

    var body: some View {
        let zone13 = detail.zone13Ms ?? 0
        let zone45 = detail.zone45Ms ?? 0
        let strength = detail.strengthActivityMs ?? 0
        let maxMs = Swift.max(zone13, zone45, strength, 1)
        let hasZones = zone13 > 0 || zone45 > 0 || strength > 0

        Card {
            WhoopSectionTitle(icon: "heart.fill", title: "Heart-rate zones", color: Theme.Chart.heartrate)
            if hasZones {
                VStack(spacing: Theme.Spacing.md) {
                    ZoneRow(label: "Zones 1–3", value: WhoopFormat.ms(zone13),
                            fraction: zone13 / maxMs, color: Theme.Chart.activity)
                    ZoneRow(label: "Zones 4–5", value: WhoopFormat.ms(zone45),
                            fraction: zone45 / maxMs, color: Theme.Chart.heartrate)
                    if strength > 0 {
                        ZoneRow(label: "Strength activity", value: WhoopFormat.ms(strength),
                                fraction: strength / maxMs, color: Theme.Chart.strain)
                    }
                }
            } else {
                Txt("No heart-rate zone time logged for this day yet.",
                    variant: .footnote, color: .labelTertiary)
            }
            Txt("Whoop reports time by zone, not a continuous daily average.",
                variant: .footnote, color: .labelTertiary)
        }
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

#if DEBUG
#Preview("Strain detail (populated)") {
    NavigationStack {
        StrainDetailScreen(date: "2026-06-06")
    }
    .environment(AppModel.sample)
}
#endif
