import SwiftUI

struct ProjectionChart: View {
    let history: [Double]
    let projection: [Double]
    var color: Color = Theme.Chart.strain
    var width: CGFloat = 300
    var height: CGFloat = 150

    private let vPadding: CGFloat = 12

    var body: some View {
        let all = history + projection
        let bounds: (lo: Double, hi: Double) = {
            guard let lo = all.min(), let hi = all.max() else { return (0, 1) }
            return lo == hi ? (lo - 1, hi + 1) : (lo, hi)
        }()
        func y(_ v: Double) -> CGFloat {
            LineGeometry.valueToY(v, min: bounds.lo, max: bounds.hi, height: height, vPadding: vPadding)
        }
        func x(_ i: Int) -> CGFloat { all.count > 1 ? CGFloat(i) / CGFloat(all.count - 1) * width : width / 2 }

        return Canvas { ctx, _ in
            guard !all.isEmpty else { return }
            let hist = (0..<history.count).map { CGPoint(x: x($0), y: y(history[$0])) }
            let startIdx = max(history.count - 1, 0)
            let proj = (startIdx..<all.count).map { CGPoint(x: x($0), y: y(all[$0])) }

            if hist.count > 1 {
                ctx.stroke(ChartCurve.smoothLine(hist), with: .color(color),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            if proj.count > 1 {
                ctx.stroke(ChartCurve.smoothLine(proj), with: .color(color.opacity(0.55)),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [4, 4]))
            }
            if let last = (history.isEmpty ? nil : CGPoint(x: x(history.count - 1), y: y(history.last!))) {
                let r: CGFloat = 4
                let d = Path(ellipseIn: CGRect(x: last.x - r, y: last.y - r, width: r * 2, height: r * 2))
                ctx.fill(d, with: .color(color))
                ctx.stroke(d, with: .color(Theme.Colors.surface), style: StrokeStyle(lineWidth: 2))
            }
        }
        .frame(width: width, height: height)
    }
}
