import SwiftUI

struct BenchmarkRangeChart: View {
    let values: [Double]
    var rangeLow: Double? = nil
    var rangeHigh: Double? = nil
    var average: Double? = nil
    var averageLabel: String? = nil
    var yTicks: [Double] = []
    var color: Color = Theme.Chart.calories
    var width: CGFloat = 320
    var height: CGFloat = 200
    var showLastDot: Bool = true

    private let vPadding: CGFloat = 14
    private var gutter: CGFloat { yTicks.isEmpty ? 0 : 34 }
    private var plotW: CGFloat { width - gutter }

    private var bounds: (lo: Double, hi: Double) {
        var all = values
        if let l = rangeLow { all.append(l) }
        if let h = rangeHigh { all.append(h) }
        if let a = average { all.append(a) }
        all.append(contentsOf: yTicks)
        guard let lo = all.min(), let hi = all.max() else { return (0, 1) }
        return lo == hi ? (lo - 1, hi + 1) : (lo, hi)
    }

    private func y(_ v: Double) -> CGFloat {
        LineGeometry.valueToY(v, min: bounds.lo, max: bounds.hi, height: height, vPadding: vPadding)
    }
    private func x(_ i: Int) -> CGFloat {
        values.count > 1 ? CGFloat(i) / CGFloat(values.count - 1) * plotW : plotW / 2
    }

    var body: some View {
        let coords = values.indices.map { CGPoint(x: x($0), y: y(values[$0])) }

        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in
                if let lo = rangeLow, let hi = rangeHigh {
                    let top = y(max(lo, hi))
                    let bot = y(min(lo, hi))
                    let band = Path(CGRect(x: 0, y: top, width: plotW, height: bot - top))
                    ctx.fill(band, with: .color(color.opacity(0.12)))
                }

                guard !coords.isEmpty else { return }
                let line = ChartCurve.smoothLine(coords)

                if let first = coords.first, let last = coords.last {
                    var area = line
                    area.addLine(to: CGPoint(x: last.x, y: height))
                    area.addLine(to: CGPoint(x: first.x, y: height))
                    area.closeSubpath()
                    ctx.fill(area, with: .linearGradient(
                        Gradient(colors: [color.opacity(0.22), color.opacity(0.0)]),
                        startPoint: CGPoint(x: 0, y: vPadding),
                        endPoint: CGPoint(x: 0, y: height)
                    ))
                }

                ctx.stroke(line, with: .color(color),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                if let avg = average {
                    let ay = y(avg)
                    var rule = Path()
                    rule.move(to: CGPoint(x: 0, y: ay))
                    rule.addLine(to: CGPoint(x: plotW, y: ay))
                    ctx.stroke(rule, with: .color(color.opacity(0.9)),
                               style: StrokeStyle(lineWidth: 1.5, dash: [2, 4]))
                }

                if showLastDot, let last = coords.last {
                    let r: CGFloat = 5
                    let dot = Path(ellipseIn: CGRect(x: last.x - r, y: last.y - r, width: r * 2, height: r * 2))
                    ctx.fill(dot, with: .color(color))
                    ctx.stroke(dot, with: .color(Theme.Colors.surface), style: StrokeStyle(lineWidth: 2.5))
                }
            }
            .frame(width: plotW, height: height)

            ForEach(Array(yTicks.enumerated()), id: \.offset) { _, tick in
                Text(Int(tick).description)
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Colors.labelTertiary)
                    .offset(x: plotW + 6, y: y(tick) - 8)
            }

            if let avg = average, let label = averageLabel {
                Text(label)
                    .font(Theme.Font.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Colors.onTint)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.Colors.label))
                    .offset(x: plotW / 2 - 28, y: y(avg) - 12)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }
}

#Preview {
    BenchmarkRangeChart(
        values: [40, 32, 45, 38, 52, 60, 55, 48, 58, 66, 72, 64, 67],
        rangeLow: 34, rangeHigh: 67,
        average: 66, averageLabel: "Avg. 66%",
        yTicks: [33, 67, 100],
        color: Theme.Chart.calories,
        width: 340, height: 220
    )
    .padding()
}
