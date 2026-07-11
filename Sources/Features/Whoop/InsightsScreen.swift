import SwiftUI

struct InsightsScreen: View {
    @Environment(AppModel.self) private var appModel
    @State private var model = InsightsViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                switch model.state {
                case .loading:
                    SkeletonCard()
                    SkeletonCard(lines: 2)
                case .lowData:
                    lowDataCard
                case .ready:
                    ForEach(model.relationships) { rel in
                        RelationshipCard(relationship: rel)
                    }
                    footnote
                }
            }
            .padding(Theme.Spacing.xl)
            .padding(.bottom, 80)
        }
        .background(Theme.Colors.background)
        .scrollIndicators(.hidden)
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.large)
        .task { await model.load(appModel: appModel) }
    }

    private var header: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                WhoopSectionTitle(icon: "chart.xyaxis.line", title: "Metric relationships",
                                  color: Theme.Chart.recovery)
                Spacer(minLength: 0)
                InfoDisclosure(
                    title: "Correlation, not causation",
                    body: "These are patterns in your own numbers over the shown window, showing how two of your metrics tended to move together. A pattern is not a cause: a relationship here doesn't mean one metric changed the other, and many things you don't see also shift these numbers. r is the strength and direction of the pattern (−1 to +1); n is how many of your days it was measured over."
                )
            }
            Txt("How your own Whoop metrics tended to move together over your last \(model.windowDays) days. Patterns in your numbers, nothing more.",
                variant: .footnote, color: .labelSecondary)
        }
    }

    private var lowDataCard: some View {
        Card {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "chart.dots.scatter")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.Colors.labelTertiary)
                Txt("Not enough days yet", variant: .bodyEmphasized, center: true)
                Txt("Relationships need at least \(model.minSamples) days of overlapping data. As Whoop syncs more days, your patterns will show up here.",
                    variant: .footnote, color: .labelSecondary, center: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
        }
    }

    private var footnote: some View {
        Txt("Each chart is one dot per day, the two metrics on a day. A tilt up-right is a positive pattern, down-right a negative one. These describe your own data over the shown window.",
            variant: .footnote, color: .labelTertiary)
    }
}

private struct RelationshipCard: View {
    let relationship: MetricRelationship

    var body: some View {
        Card(metricAccent: relationship.accent) {
            HStack(alignment: .firstTextBaseline) {
                Txt(relationship.title, variant: .bodyEmphasized)
                Spacer(minLength: 0)
                SignificanceChip(significant: relationship.significant)
            }

            Txt(relationship.plainLanguage, variant: .subhead, color: .labelSecondary)

            HStack(alignment: .center, spacing: Theme.Spacing.lg) {
                ScatterPlot(points: relationship.scatter, color: relationship.accent)
                    .frame(width: 132, height: 96)
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    StatReadout(label: "r", value: relationship.rText, accent: relationship.accent)
                    StatReadout(label: "n", value: "\(relationship.n) days")
                    if relationship.lagged {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.Colors.labelTertiary)
                            Txt("next-day", variant: .footnote, color: .labelTertiary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// A small label-over-value readout for the r / n stats. `accent` tints the value when set.
private struct StatReadout: View {
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

/// A pill stating whether the pattern clears the ~0.05 significance bar at this n. "significant" /
/// "not significant" describes the statistic, never the person.
private struct SignificanceChip: View {
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

/// A compact scatter of the paired days, each point normalized 0–1 within its own axis so the two
/// units share the box. No trend line is drawn. The r already carries the strength.
private struct ScatterPlot: View {
    let points: [CGPoint]
    let color: Color

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 6
            let w = size.width - inset * 2
            let h = size.height - inset * 2

            let frame = Path(roundedRect: CGRect(x: inset, y: inset, width: w, height: h),
                             cornerRadius: 8)
            context.stroke(frame, with: .color(Theme.Colors.separator), lineWidth: 1)

            for p in points {
                let cx = inset + p.x * w
                let cy = inset + (1 - p.y) * h
                let dot = Path(ellipseIn: CGRect(x: cx - 3, y: cy - 3, width: 6, height: 6))
                context.fill(dot, with: .color(color.opacity(0.85)))
            }
        }
        .accessibilityHidden(true)
    }
}

/// One computed metric pair, ready to render. Display strings are built in the view-model so the
/// card stays declarative.
struct MetricRelationship: Identifiable {
    let id: String
    let title: String
    let plainLanguage: String
    let r: Double
    let n: Int
    let significant: Bool
    let lagged: Bool
    let accent: Color
    let scatter: [CGPoint]

    var rText: String { (r >= 0 ? "+" : "") + String(format: "%.2f", r) }
}

@MainActor
@Observable
final class InsightsViewModel {
    enum State: Equatable { case loading, ready, lowData }

    private(set) var state: State = .loading
    private(set) var relationships: [MetricRelationship] = []
    private(set) var windowDays = SampleData.insightsDayCount

    /// Minimum overlapping days before we show a pair's r.
    let minSamples = 8

    /// One pair to correlate: two series (date-aligned by index, oldest first; nil = no data that
    /// day), axis labels for the plain-language sentence, the hue, and whether it's the lagged
    /// (today → tomorrow) pair.
    private struct PairSpec {
        let id: String
        let title: String
        let xLabel: String
        let yLabel: String
        let accent: Color
        let lagged: Bool
        let x: () -> [Double?]
        let y: () -> [Double?]
    }

    func load(appModel: AppModel) async {
        state = .loading
        let recovery: [Double?]
        let hrv: [Double?]
        let rhr: [Double?]
        let sleep: [Double?]
        let strain: [Double?]
        if appModel.usesSampleData {
            recovery = SampleData.recoveryHistory
            hrv = SampleData.hrvHistory
            rhr = SampleData.rhrHistory
            sleep = SampleData.sleepPerformanceHistory
            strain = SampleData.strainHistory
        } else {
            let days = SampleData.insightsDayCount
            recovery = await appModel.whoop.history(metric: .recovery, days: days).map(\.value)
            hrv = await appModel.whoop.history(metric: .hrv, days: days).map(\.value)
            rhr = await appModel.whoop.history(metric: .rhr, days: days).map(\.value)
            strain = await appModel.whoop.history(metric: .strain, days: days).map(\.value)
            sleep = Array(repeating: nil, count: recovery.count)
        }
        windowDays = recovery.count

        let specs: [PairSpec] = [
            PairSpec(id: "sleep-recovery", title: "Sleep & Recovery",
                     xLabel: "sleep performance", yLabel: "recovery",
                     accent: Theme.Chart.sleep, lagged: false,
                     x: { sleep }, y: { recovery }),
            PairSpec(id: "hrv-recovery", title: "HRV & Recovery",
                     xLabel: "HRV", yLabel: "recovery",
                     accent: Theme.Chart.recovery, lagged: false,
                     x: { hrv }, y: { recovery }),
            PairSpec(id: "rhr-recovery", title: "Resting HR & Recovery",
                     xLabel: "resting heart rate", yLabel: "recovery",
                     accent: Theme.Chart.heartrate, lagged: false,
                     x: { rhr }, y: { recovery }),
            PairSpec(id: "strain-recovery", title: "Strain & Recovery",
                     xLabel: "strain", yLabel: "recovery",
                     accent: Theme.Chart.strain, lagged: false,
                     x: { strain }, y: { recovery }),
            PairSpec(id: "strain-next-recovery", title: "Today's strain → tomorrow's recovery",
                     xLabel: "strain", yLabel: "next-day recovery",
                     accent: Theme.Chart.calories, lagged: true,
                     x: { strain }, y: { recovery }),
        ]

        relationships = specs.compactMap { build($0) }
        state = relationships.isEmpty ? .lowData : .ready
    }

    private func build(_ spec: PairSpec) -> MetricRelationship? {
        let xRaw = spec.x()
        let yRaw = spec.y()
        let (xShifted, yShifted): ([Double?], [Double?]) = spec.lagged
            ? (Array(xRaw.dropLast()), Array(yRaw.dropFirst()))
            : (xRaw, yRaw)
        var xPaired: [Double] = []
        var yPaired: [Double] = []
        for (x, y) in zip(xShifted, yShifted) {
            guard let x, let y else { continue }
            xPaired.append(x)
            yPaired.append(y)
        }

        guard let result = CorrelationMath.pearson(xPaired, yPaired),
              result.n >= minSamples else { return nil }

        return MetricRelationship(
            id: spec.id,
            title: spec.title,
            plainLanguage: plainLanguage(spec: spec, r: result.r),
            r: result.r,
            n: result.n,
            significant: CorrelationMath.isSignificant(r: result.r, n: result.n),
            lagged: spec.lagged,
            accent: spec.accent,
            scatter: normalize(x: xPaired, y: yPaired)
        )
    }

    /// Builds a strictly observational sentence: the strength/direction band plus an "on higher-X
    /// days, your Y tended to be higher/lower" restatement. Never causal, never advice.
    private func plainLanguage(spec: PairSpec, r: Double) -> String {
        let band = CorrelationMath.describe(r: r)
        if abs(r) < 0.1 {
            return "Over this window your \(spec.xLabel) and \(spec.yLabel) showed \(band)."
        }
        let tendedTo = r >= 0 ? "higher" : "lower"
        return "\(band.prefix(1).uppercased() + band.dropFirst()): on days with higher \(spec.xLabel), your \(spec.yLabel) tended to be \(tendedTo)."
    }

    /// Min-max normalize each axis to 0…1 so the two units share the scatter box. Flat axes collapse
    /// to 0.5 (no spread to show) rather than dividing by zero.
    private func normalize(x: [Double], y: [Double]) -> [CGPoint] {
        let nx = scale(x)
        let ny = scale(y)
        return zip(nx, ny).map { CGPoint(x: $0, y: $1) }
    }

    private func scale(_ values: [Double]) -> [Double] {
        guard let lo = values.min(), let hi = values.max(), hi > lo else {
            return values.map { _ in 0.5 }
        }
        return values.map { ($0 - lo) / (hi - lo) }
    }
}

#if DEBUG
#Preview("Insights · relationships") {
    NavigationStack {
        InsightsScreen()
            .environment(AppModel.sample)
    }
}
#endif
