import SwiftUI

struct ChartLegend: View {
    let items: [(label: String, color: Color)]
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ForEach(items.indices, id: \.self) { i in
                HStack(spacing: 5) {
                    Circle().fill(items[i].color).frame(width: 8, height: 8)
                    Text(items[i].label)
                        .font(Theme.Font.footnote)
                        .foregroundStyle(Theme.Colors.labelSecondary)
                }
            }
        }
    }
}

struct DualRingGauge: View {
    let outer: Double
    let inner: Double
    var outerColor: Color = Theme.Chart.recovery
    var innerColor: Color = Theme.Chart.strain
    var title: String
    var caption: String? = nil
    var size: CGFloat = 168
    var lineWidth: CGFloat = 12

    var body: some View {
        ZStack {
            ring(outer, outerColor, inset: 0)
            ring(inner, innerColor, inset: lineWidth + 6)
            VStack(spacing: 2) {
                Text(title).font(Theme.Font.metricNumber).foregroundStyle(Theme.Colors.label)
                if let caption {
                    Text(caption).font(Theme.Font.subhead).foregroundStyle(Theme.Colors.labelSecondary)
                }
            }
        }
        .frame(width: size, height: size)
    }

    private func ring(_ progress: Double, _ color: Color, inset: CGFloat) -> some View {
        ZStack {
            Circle().stroke(Theme.Colors.fieldBackground, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0.001), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(inset)
    }
}

struct PieChart: View {
    let values: [Double]
    var colors: [Color] = [Theme.Chart.recovery, Theme.Chart.strain, Theme.Chart.sleep, Theme.Chart.calories]
    var size: CGFloat = 140

    var body: some View {
        Canvas { ctx, _ in
            let total = max(values.reduce(0, +), 0.0001)
            let c = CGPoint(x: size / 2, y: size / 2)
            let r = size / 2
            var start = -90.0
            for (i, v) in values.enumerated() {
                let sweep = v / total * 360
                var p = Path()
                p.move(to: c)
                p.addArc(center: c, radius: r, startAngle: .degrees(start),
                         endAngle: .degrees(start + sweep), clockwise: false)
                p.closeSubpath()
                ctx.fill(p, with: .color(colors[i % colors.count]))
                start += sweep
            }
        }
        .frame(width: size, height: size)
    }
}
