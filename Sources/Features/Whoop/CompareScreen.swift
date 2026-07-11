import SwiftUI

struct CompareScreen: View {
    @Environment(AppModel.self) private var appModel
    @State private var model = CompareViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                pickerCard
                switch model.state {
                case .loading:
                    SkeletonCard()
                    SkeletonCard(lines: 2)
                case .empty:
                    emptyCard
                case .ready:
                    chartCard
                    readoutCard
                    footnote
                }
            }
            .padding(Theme.Spacing.xl)
            .padding(.bottom, 80)
        }
        .background(Theme.Colors.background)
        .scrollIndicators(.hidden)
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.large)
        .task { await model.load(appModel: appModel) }
    }

    private var header: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                WhoopSectionTitle(icon: "square.on.square", title: "Overlay your metrics",
                                  color: Theme.Chart.recovery)
                Spacer(minLength: 0)
                InfoDisclosure(
                    title: "Reading this chart",
                    body: "Correlation, not causation. Each line is one of your own metrics over your last \(model.windowDays) days, normalized to a 0 to 1 scale so different units (percent, ms, bpm) can share one axis. Lines moving together is a pattern in your own data, not a cause."
                )
            }
            Txt("Pick two or three of your own metrics to overlay them on one shared axis and see how they moved together.",
                variant: .footnote, color: .labelSecondary)
        }
    }

    private var pickerCard: some View {
        Card {
            Txt("Metrics", variant: .footnote, color: .labelSecondary)
            CompareChipFlow(
                metrics: CompareMetric.allCases,
                selected: model.selected,
                atCap: model.atCap,
                onToggle: { model.toggle($0) }
            )
            Txt(model.atCap
                ? "Three metrics is the max for a readable overlay. Deselect one to swap."
                : "Select \(model.selected.count == 1 ? "one more" : "up to three").",
                variant: .footnote, color: .labelTertiary)
        }
    }

    private var chartCard: some View {
        Card {
            HStack {
                WhoopSectionTitle(icon: "chart.xyaxis.line", title: "On one axis",
                                  color: Theme.Chart.recovery)
                Spacer(minLength: 0)
            }
            NormalizedOverlayChart(series: model.chartSeries, animate: !reduceMotion)
                .frame(height: 188)
                .frame(maxWidth: .infinity)
                .padding(.top, Theme.Spacing.xs)
            CompareLegend(series: model.chartSeries)
            if !model.missingSelected.isEmpty {
                Txt("Not enough synced days yet to draw \(model.missingSelected.map(\.shortName).joined(separator: ", ")).",
                    variant: .footnote, color: .labelTertiary)
            }
            Txt("Normalized to a 0 to 1 scale per metric, oldest day on the left.",
                variant: .footnote, color: .labelTertiary)
        }
    }

    private var emptyCard: some View {
        Card {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "square.on.square")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.Colors.labelTertiary)
                Txt("Not enough days yet", variant: .bodyEmphasized, center: true)
                Txt("The overlay needs at least two days of data per metric. As Whoop syncs more days, your lines will show up here.",
                    variant: .footnote, color: .labelSecondary, center: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
        }
    }

    @ViewBuilder
    private var readoutCard: some View {
        if let pair = model.pairReadout {
            Card(metricAccent: pair.accent) {
                HStack(alignment: .firstTextBaseline) {
                    WhoopSectionTitle(icon: "arrow.left.arrow.right", title: "How they move together",
                                      color: pair.accent)
                    Spacer(minLength: 0)
                    CompareSignificanceChip(significant: pair.significant)
                }
                Txt(pair.plainLanguage, variant: .subhead, color: .labelSecondary)
                HStack(spacing: Theme.Spacing.xl) {
                    CompareStat(label: "r", value: pair.rText, accent: pair.accent)
                    CompareStat(label: "n", value: "\(pair.n) days")
                }
            }
        } else if model.selected.count >= 3 {
            Card {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Colors.labelTertiary)
                    Txt("Select two metrics to see how they relate.",
                        variant: .footnote, color: .labelSecondary)
                }
            }
        } else if model.selected.count == 2 {
            Card {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Colors.labelTertiary)
                    Txt("Not enough overlapping days yet. This readout needs at least \(model.minSamples) days where both metrics have data.",
                        variant: .footnote, color: .labelSecondary)
                }
            }
        }
    }

    private var footnote: some View {
        Txt("These lines describe your own data over the shown window. r is the strength and direction of the pattern (−1 to +1); n is how many days it covers.",
            variant: .footnote, color: .labelTertiary)
    }
}

/// Two-row wrap of metric chips. Selected chips fill with the metric's hue; unselected chips dim and
/// disable once the selection cap is reached, so only a swap (deselect then reselect) is possible.
private struct CompareChipFlow: View {
    let metrics: [CompareMetric]
    let selected: Set<CompareMetric>
    let atCap: Bool
    let onToggle: (CompareMetric) -> Void

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: Theme.Spacing.sm)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.sm) {
            ForEach(metrics) { metric in
                let isSelected = selected.contains(metric)
                let disabled = atCap && !isSelected
                CompareChip(metric: metric, selected: isSelected, disabled: disabled) {
                    onToggle(metric)
                }
            }
        }
    }
}

private struct CompareChip: View {
    let metric: CompareMetric
    let selected: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                Circle()
                    .fill(selected ? Theme.Colors.onTint : metric.hue)
                    .frame(width: 8, height: 8)
                Text(metric.shortName)
                    .font(Theme.Font.subhead.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? Theme.Colors.onTint
                             : (disabled ? Theme.Colors.labelTertiary : Theme.Colors.labelSecondary))
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(maxWidth: .infinity)
            .background(
                Capsule().fill(selected ? metric.hue : Theme.Colors.fieldBackground)
            )
            .opacity(disabled ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(metric.fullName)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(disabled ? "Three metrics already selected. Deselect one to choose this." : "Toggles this metric in the overlay")
    }
}

private struct CompareLegend: View {
    let series: [CompareSeries]

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            ForEach(series) { s in
                HStack(spacing: Theme.Spacing.xs) {
                    Capsule()
                        .fill(s.metric.hue)
                        .frame(width: 14, height: 3)
                    Txt(s.metric.shortName, variant: .footnote, color: .labelSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }
}

/// Label + value readout for the r / n stats. Kept local so the screens stay independent;
/// `accent` tints the value when set.
private struct CompareStat: View {
    let label: String
    let value: String
    var accent: Color?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            Text(label)
                .font(Theme.Font.bodyEmphasized)
                .foregroundStyle(Theme.Colors.labelTertiary)
            Text(value)
                .font(Theme.Font.statNumber)
                .monospacedDigit()
                .foregroundStyle(accent ?? Theme.Colors.label)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }
}

/// Pill stating whether the pattern clears the ~0.05 significance bar at this n. The wording describes
/// the statistic, never the person. Kept local so the two screens stay independent.
private struct CompareSignificanceChip: View {
    let significant: Bool

    var body: some View {
        let color = significant ? Theme.Colors.tint : Theme.Colors.labelTertiary
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: significant ? "checkmark.seal.fill" : "questionmark.circle")
                .font(.system(size: 11, weight: .semibold))
            Text(significant ? "significant" : "not significant")
                .font(Theme.Font.footnote.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Capsule().fill(color.opacity(0.12)))
        .accessibilityLabel(significant ? "Statistically significant at the 0.05 level" : "Not statistically significant")
    }
}

/// Compact multi-line chart. Each `CompareSeries` is already normalized to 0…1, so all lines share one
/// vertical axis and the same day index on x. Under Reduce Motion the lines render fully (no draw-in).
private struct NormalizedOverlayChart: View {
    let series: [CompareSeries]
    let animate: Bool

    /// 0→1 draw-in progress for the trailing edge of every line; Reduce Motion stays at 1.
    @State private var progress: CGFloat = 0

    var body: some View {
        OverlayCanvas(series: series, animate: animate, progress: progress)
            .onAppear {
                guard animate else { progress = 1; return }
                progress = 0
                withAnimation(.easeOut(duration: 0.7)) { progress = 1 }
            }
            .onChange(of: series.map(\.metric)) { _, _ in
                guard animate else { progress = 1; return }
                progress = 0
                withAnimation(.easeOut(duration: 0.7)) { progress = 1 }
            }
            .accessibilityHidden(true)
    }
}

/// Split out so `Animatable` can interpolate `progress`. A Canvas closure only re-executes on discrete
/// state changes, so without this the draw-in would snap to fully drawn in one frame instead of sweeping.
private struct OverlayCanvas: View, Animatable {
    let series: [CompareSeries]
    let animate: Bool
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 8
            let plot = CGRect(x: inset, y: inset,
                              width: size.width - inset * 2,
                              height: size.height - inset * 2)

            let frame = Path(roundedRect: plot, cornerRadius: 10)
            context.stroke(frame, with: .color(Theme.Colors.separator), lineWidth: 1)
            for y in [plot.minY, plot.maxY] {
                var guide = Path()
                guide.move(to: CGPoint(x: plot.minX, y: y))
                guide.addLine(to: CGPoint(x: plot.maxX, y: y))
                context.stroke(guide, with: .color(Theme.Colors.separator.opacity(0.5)), lineWidth: 1)
            }

            for s in series {
                let pts = points(for: s.normalized, in: plot)
                guard pts.count >= 2 else { continue }
                let full = linePath(pts)
                let drawn = animate ? full.trimmedPath(from: 0, to: progress) : full
                context.stroke(
                    drawn,
                    with: .color(s.metric.hue),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                )
                if progress >= 0.999 || !animate, let last = pts.last {
                    let dot = Path(ellipseIn: CGRect(x: last.x - 3, y: last.y - 3, width: 6, height: 6))
                    context.fill(dot, with: .color(s.metric.hue))
                }
            }
        }
    }

    /// Map 0…1 values to plot points across the shared day axis (oldest left, newest right). Each value
    /// sits at its own day's x so lines stay calendar-aligned; nil days are skipped, never plotted.
    private func points(for values: [Double?], in plot: CGRect) -> [CGPoint] {
        guard values.count >= 2 else { return [] }
        let stepX = plot.width / CGFloat(values.count - 1)
        return values.enumerated().compactMap { i, v in
            v.map { CGPoint(x: plot.minX + CGFloat(i) * stepX,
                            y: plot.maxY - CGFloat($0) * plot.height) }
        }
    }

    private func linePath(_ pts: [CGPoint]) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        for p in pts.dropFirst() { path.addLine(to: p) }
        return path
    }
}

/// A Whoop metric the overlay can plot. Each case carries its display names, its `Theme.Chart` hue, its
/// `WhoopHistoryMetric` mapping for real builds, and its seeded series for the `.sample` container.
enum CompareMetric: String, CaseIterable, Identifiable, Hashable {
    case recovery, hrv, restingHR, sleep, strain

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .recovery: return "Recovery"
        case .hrv: return "HRV"
        case .restingHR: return "Resting HR"
        case .sleep: return "Sleep"
        case .strain: return "Strain"
        }
    }

    var fullName: String {
        switch self {
        case .recovery: return "Recovery"
        case .hrv: return "Heart rate variability"
        case .restingHR: return "Resting heart rate"
        case .sleep: return "Sleep performance"
        case .strain: return "Day strain"
        }
    }

    /// The per-metric line hue. HRV borrows recovery's cyan family but reads distinct against the
    /// other lines; resting HR is heart-rate red, sleep purple, strain blue.
    var hue: Color {
        switch self {
        case .recovery: return Theme.Chart.recovery
        case .hrv: return Theme.Chart.activity
        case .restingHR: return Theme.Chart.heartrate
        case .sleep: return Theme.Chart.sleep
        case .strain: return Theme.Chart.strain
        }
    }

    /// The cached Whoop history series this metric reads in a real build, or nil when there's no
    /// equivalent (sleep performance), which degrades to an empty line instead of fabricated values.
    var whoopMetric: WhoopHistoryMetric? {
        switch self {
        case .recovery: return .recovery
        case .hrv: return .hrv
        case .restingHR: return .rhr
        case .sleep: return nil
        case .strain: return .strain
        }
    }

    /// This metric's 21-day seeded history, for the `.sample` container only. Real builds read the
    /// cached Whoop history instead (`CompareViewModel.load`), never these seeded numbers.
    var sampleHistory: [Double] {
        switch self {
        case .recovery: return SampleData.recoveryHistory
        case .hrv: return SampleData.hrvHistory
        case .restingHR: return SampleData.rhrHistory
        case .sleep: return SampleData.sleepPerformanceHistory
        case .strain: return SampleData.strainHistory
        }
    }
}

/// A metric paired with its normalized line (0…1, one slot per day, oldest first; nil = no data),
/// ready for the chart and legend.
struct CompareSeries: Identifiable {
    let metric: CompareMetric
    let normalized: [Double?]
    var id: String { metric.id }
}

/// The pairwise "how they move together" readout when exactly two metrics are selected.
struct ComparePairReadout {
    let r: Double
    let n: Int
    let significant: Bool
    let plainLanguage: String
    let accent: Color

    var rText: String { (r >= 0 ? "+" : "") + String(format: "%.2f", r) }
}

@MainActor
@Observable
final class CompareViewModel {
    enum State: Equatable { case loading, ready, empty }

    private(set) var state: State = .loading

    /// The currently-selected metrics. Default = Recovery + HRV (the headline pair).
    private(set) var selected: Set<CompareMetric> = [.recovery, .hrv]

    /// Each metric's daily series over the window (index = calendar day, oldest first, nil = no data),
    /// filled by `load`.
    private var series: [CompareMetric: [Double?]] = [:]

    /// Legibility cap: at most three lines on one axis.
    let maxSelected = 3
    var atCap: Bool { selected.count >= maxSelected }

    /// Minimum overlapping days before the pair readout shows an r; avoids a noisy r over a handful
    /// of days.
    let minSamples = 8

    private(set) var windowDays = SampleData.insightsDayCount

    /// Source the aligned daily series. The sample container serves the seeded 21-day history; real
    /// builds read the cached Whoop history the client already stores (only the user's own numbers).
    /// `history` returns one point per calendar day (oldest first, nil = no data), keeping the series
    /// date-aligned by index across metrics. The awaits run sequentially on purpose: each walks the
    /// same dates and the per-day summary cache makes the later passes nearly free, keeping request
    /// volume within Whoop's rate limits.
    func load(appModel: AppModel) async {
        state = .loading
        var next: [CompareMetric: [Double?]] = [:]
        if appModel.usesSampleData {
            for metric in CompareMetric.allCases {
                next[metric] = metric.sampleHistory
            }
        } else {
            let days = SampleData.insightsDayCount
            for metric in CompareMetric.allCases {
                if let whoopMetric = metric.whoopMetric {
                    next[metric] = await appModel.whoop.history(metric: whoopMetric, days: days).map(\.value)
                } else {
                    next[metric] = Array(repeating: Double?.none, count: days)
                }
            }
        }
        series = next
        windowDays = next[.recovery]?.count ?? SampleData.insightsDayCount
        let anyDrawable = CompareMetric.allCases.contains { realDayCount($0) >= 2 }
        state = anyDrawable ? .ready : .empty
    }

    /// How many days of this metric's series actually carry a value.
    private func realDayCount(_ metric: CompareMetric) -> Int {
        (series[metric] ?? []).compactMap { $0 }.count
    }

    /// Selected metrics with too few real days to draw a line; the chart card names them explicitly
    /// instead of silently dropping the line.
    var missingSelected: [CompareMetric] {
        CompareMetric.allCases.filter { selected.contains($0) && realDayCount($0) < 2 }
    }

    /// Toggle a metric in/out, enforcing the cap. A selected chip always deselects; an unselected one
    /// adds only when under the cap. Keeps at least one selected so the chart is never empty.
    func toggle(_ metric: CompareMetric) {
        if selected.contains(metric) {
            if selected.count > 1 { selected.remove(metric) }
        } else if !atCap {
            selected.insert(metric)
        }
    }

    /// The normalized series for the chart, in declaration order so the legend and lines stay stable
    /// as the user toggles.
    var chartSeries: [CompareSeries] {
        CompareMetric.allCases
            .filter { selected.contains($0) }
            .map { CompareSeries(metric: $0, normalized: Self.normalize(series[$0] ?? [])) }
    }

    /// The pairwise readout, only when exactly two metrics are selected. With three it's omitted and
    /// the view shows a "select two" note instead.
    var pairReadout: ComparePairReadout? {
        let pair = CompareMetric.allCases.filter { selected.contains($0) }
        guard pair.count == 2 else { return nil }
        let a = pair[0], b = pair[1]
        var aPaired: [Double] = []
        var bPaired: [Double] = []
        for (x, y) in zip(series[a] ?? [], series[b] ?? []) {
            guard let x, let y else { continue }
            aPaired.append(x)
            bPaired.append(y)
        }
        guard let result = CorrelationMath.pearson(aPaired, bPaired),
              result.n >= minSamples else { return nil }
        return ComparePairReadout(
            r: result.r,
            n: result.n,
            significant: CorrelationMath.isSignificant(r: result.r, n: result.n),
            plainLanguage: Self.plainLanguage(a: a, b: b, r: result.r),
            accent: a.hue
        )
    }

    /// A strictly observational sentence describing how the two series moved together over the window:
    /// the descriptive band plus a "rose and fell together / moved opposite" restatement.
    /// Never causal, never advice.
    private static func plainLanguage(a: CompareMetric, b: CompareMetric, r: Double) -> String {
        let band = CorrelationMath.describe(r: r)
        if abs(r) < 0.1 {
            return "Over this window your \(a.shortName.lowercased()) and \(b.shortName.lowercased()) showed \(band)."
        }
        let together = r >= 0
            ? "these two tended to rise and fall together"
            : "when one was higher the other tended to be lower"
        return "\(band.prefix(1).uppercased() + band.dropFirst()): \(together)."
    }

    /// Min-max normalize a series to 0…1 so different units share the chart's vertical axis (nil days
    /// stay nil). A flat series (no spread) collapses to the mid-line rather than dividing by zero.
    static func normalize(_ values: [Double?]) -> [Double?] {
        let real = values.compactMap { $0 }
        guard let lo = real.min(), let hi = real.max(), hi > lo else {
            return values.map { $0.map { _ in 0.5 } }
        }
        return values.map { $0.map { ($0 - lo) / (hi - lo) } }
    }
}

#if DEBUG
#Preview("Compare · overlay") {
    NavigationStack {
        CompareScreen()
            .environment(AppModel.sample)
    }
}
#endif
