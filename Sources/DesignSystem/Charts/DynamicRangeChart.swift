import SwiftUI

struct DynamicRangeChart: View {
    let values: [Double]
    let lower: [Double]
    let upper: [Double]
    var color: Color = Theme.Chart.calories
    var width: CGFloat = 300
    var height: CGFloat = 180

    private let vPadding: CGFloat = 14

    private var bounds: (lo: Double, hi: Double) {
        let all = values + lower + upper
        guard let lo = all.min(), let hi = all.max() else { return (0, 1) }
        return lo == hi ? (lo - 1, hi + 1) : (lo, hi)
    }
    private func yOf(_ v: Double) -> CGFloat {
        LineGeometry.valueToY(v, min: bounds.lo, max: bounds.hi, height: height, vPadding: vPadding)
    }
    private func xOf(_ i: Int, _ count: Int) -> CGFloat {
        count > 1 ? CGFloat(i) / CGFloat(count - 1) * width : width / 2
    }

    var body: some View {
        let vc = values.indices.map { CGPoint(x: xOf($0, values.count), y: yOf(values[$0])) }
        let uc = upper.indices.map { CGPoint(x: xOf($0, upper.count), y: yOf(upper[$0])) }
        let lc = lower.indices.map { CGPoint(x: xOf($0, lower.count), y: yOf(lower[$0])) }

        Canvas { ctx, _ in
            if !uc.isEmpty, !lc.isEmpty {
                var band = ChartCurve.smoothLine(uc)
                for p in lc.reversed() { band.addLine(to: p) }
                band.closeSubpath()
                ctx.fill(band, with: .color(color.opacity(0.14)))
            }
            guard !vc.isEmpty else { return }
            let line = ChartCurve.smoothLine(vc)
            ctx.stroke(line, with: .color(color),
                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            for p in vc {
                let r: CGFloat = 3
                let d = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                ctx.fill(d, with: .color(Theme.Colors.surface))
                ctx.stroke(d, with: .color(color), style: StrokeStyle(lineWidth: 2))
            }
        }
        .frame(width: width, height: height)
    }
}
