import SwiftUI

struct ScoreCard: View {
    let title: String
    let value: String
    let date: String
    let rangeLabel: String
    let metrics: [String]
    let series: [Double]
    var rangeLow: Double
    var rangeHigh: Double
    var average: Double
    var averageLabel: String
    var yTicks: [Double] = []
    var color: Color = Theme.Chart.calories

    @State private var selected = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(value).font(Theme.Font.metricNumber).foregroundStyle(Theme.Colors.label)
                    Text(date).font(Theme.Font.footnote).foregroundStyle(Theme.Colors.labelTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Normal range").font(Theme.Font.subhead.weight(.medium))
                        .foregroundStyle(Theme.Chart.activity)
                    Text(rangeLabel).font(Theme.Font.footnote).foregroundStyle(Theme.Colors.labelSecondary)
                }
            }

            SegmentedPills(options: metrics, selection: $selected)

            BenchmarkRangeChart(
                values: series, rangeLow: rangeLow, rangeHigh: rangeHigh,
                average: average, averageLabel: averageLabel, yTicks: yTicks,
                color: color, width: 300, height: 190
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.Colors.surface))
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 6)
    }
}
