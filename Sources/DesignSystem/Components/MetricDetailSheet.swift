import SwiftUI

struct MetricDetailSheet: View {
    let title: String
    let value: String
    let unit: String?
    let date: String
    /// Optional caption for the "vs your typical" chip (e.g. "34 – 67"). When nil the chip is hidden.
    let rangeLabel: String?
    let series: [Double]
    let labels: [String]
    /// Lower / upper bound of the user's personal typical band (soft shaded area in the chart).
    let rangeLow: Double?
    let rangeHigh: Double?
    let color: Color
    /// Optional pill selector titles. When nil the selector row is hidden.
    let pills: [String]?
    let statStripItems: [MetricStatStrip.Item]
    /// Optional personal goal, drawn as a horizontal dashed reference line over the chart.
    let goalLine: Double?
    var onClose: () -> Void

    init(
        title: String,
        value: String,
        unit: String? = nil,
        date: String,
        rangeLabel: String? = nil,
        series: [Double],
        labels: [String],
        rangeLow: Double? = nil,
        rangeHigh: Double? = nil,
        color: Color,
        pills: [String]? = nil,
        statStripItems: [MetricStatStrip.Item],
        goalLine: Double? = nil,
        onClose: @escaping () -> Void = {}
    ) {
        self.title = title
        self.value = value
        self.unit = unit
        self.date = date
        self.rangeLabel = rangeLabel
        self.series = series
        self.labels = labels
        self.rangeLow = rangeLow
        self.rangeHigh = rangeHigh
        self.color = color
        self.pills = pills
        self.statStripItems = statStripItems
        self.goalLine = goalLine
        self.onClose = onClose
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pill = 0
    @State private var appeared = false

    private let chartWidth: CGFloat = 330
    private let chartHeight: CGFloat = 230
    private let chartVPadding: CGFloat = 16

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                SheetHeader(title: title, onClose: onClose)

                hero

                MetricStatStrip(items: statStripItems)

                if let pills {
                    SegmentedPills(options: pills, selection: $pill)
                }

                chart
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .presentationCornerRadius(28)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.98)
        .opacity(appeared || reduceMotion ? 1 : 0)
        .onAppear {
            guard !reduceMotion else { appeared = true; return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { appeared = true }
        }
    }

    private var hero: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(Theme.Font.heroNumber)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(Theme.Colors.label)
                    if let unit {
                        Text(unit)
                            .font(Theme.Font.bodyEmphasized)
                            .foregroundStyle(Theme.Colors.labelTertiary)
                    }
                }
                Text(date).font(Theme.Font.footnote).foregroundStyle(Theme.Colors.labelTertiary)
            }
            Spacer()
            if let rangeLabel {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("vs your typical")
                        .font(Theme.Font.subhead.weight(.medium))
                        .foregroundStyle(color)
                    Text(rangeLabel)
                        .font(Theme.Font.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Colors.labelSecondary)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Capsule().fill(color.opacity(0.10)))
            }
        }
    }

    private var chart: some View {
        ZStack(alignment: .topLeading) {
            InteractiveLineChart(
                values: series, labels: labels,
                rangeLow: rangeLow, rangeHigh: rangeHigh,
                color: color, width: chartWidth, height: chartHeight
            )
            if let goalLine, let y = goalY(goalLine) {
                goalDash(at: y)
            }
        }
        .frame(width: chartWidth, height: chartHeight, alignment: .topLeading)
    }

    private func goalY(_ goal: Double) -> CGFloat? {
        var all = series
        if let l = rangeLow { all.append(l) }
        if let h = rangeHigh { all.append(h) }
        guard let lo = all.min(), let hi = all.max() else { return nil }
        let (bLo, bHi) = lo == hi ? (lo - 1, hi + 1) : (lo, hi)
        guard goal >= bLo, goal <= bHi else { return nil }
        return LineGeometry.valueToY(goal, min: bLo, max: bHi, height: chartHeight, vPadding: chartVPadding)
    }

    private func goalDash(at y: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            Path { p in
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: chartWidth, y: y))
            }
            .stroke(color.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            Text("Goal")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(color.opacity(0.12)))
                .offset(y: y - 9)
        }
        .frame(width: chartWidth, height: chartHeight, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

#if DEBUG
#Preview {
    MetricDetailSheet(
        title: "Strain Score",
        value: "65",
        unit: "%",
        date: "Feb 19, 2025",
        rangeLabel: "34 – 67",
        series: [40, 32, 45, 38, 52, 60, 55, 48, 58, 66, 72, 64, 67],
        labels: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13"],
        rangeLow: 34, rangeHigh: 67,
        color: Theme.Chart.calories,
        pills: ["Strain score", "Exercise Duration", "Daytime HR"],
        statStripItems: [
            .init(label: "Peak", value: "72", unit: "%"),
            .init(label: "Duration", value: "48", unit: "min"),
            .init(label: "Avg HR", value: "118", unit: "bpm")
        ],
        goalLine: 60
    )
}
#endif
