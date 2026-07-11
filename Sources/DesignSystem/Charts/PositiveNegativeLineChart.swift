import SwiftUI

struct PositiveNegativeLineChart: View {
    let values: [Double]
    var threshold: Double = 0
    var positiveColor: Color = Theme.Chart.activity
    var negativeColor: Color = Theme.Chart.calories
    var width: CGFloat = 300
    var height: CGFloat = 160

    private let vPadding: CGFloat = 12

    private var bounds: (lo: Double, hi: Double) {
        let all = values + [threshold]
        guard let lo = all.min(), let hi = all.max() else { return (0, 1) }
        return lo == hi ? (lo - 1, hi + 1) : (lo, hi)
    }
    private func yOf(_ v: Double) -> CGFloat {
        LineGeometry.valueToY(v, min: bounds.lo, max: bounds.hi, height: height, vPadding: vPadding)
    }

    var body: some View {
        let coords = values.indices.map {
            CGPoint(x: values.count > 1 ? CGFloat($0) / CGFloat(values.count - 1) * width : width / 2,
                    y: yOf(values[$0]))
        }
        Canvas { ctx, _ in
            guard let f = coords.first, let l = coords.last else { return }
            let ty = yOf(threshold)
            let line = ChartCurve.smoothLine(coords)
            var area = line
            area.addLine(to: CGPoint(x: l.x, y: ty))
            area.addLine(to: CGPoint(x: f.x, y: ty))
            area.closeSubpath()

            var top = ctx
            top.clip(to: Path(CGRect(x: 0, y: 0, width: width, height: ty)))
            top.fill(area, with: .color(positiveColor.opacity(0.22)))
            var bot = ctx
            bot.clip(to: Path(CGRect(x: 0, y: ty, width: width, height: height - ty)))
            bot.fill(area, with: .color(negativeColor.opacity(0.22)))

            var base = Path()
            base.move(to: CGPoint(x: 0, y: ty)); base.addLine(to: CGPoint(x: width, y: ty))
            ctx.stroke(base, with: .color(Theme.Colors.borderStrong), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

            ctx.stroke(line, with: .color(Theme.Colors.label.opacity(0.7)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .frame(width: width, height: height)
    }
}
