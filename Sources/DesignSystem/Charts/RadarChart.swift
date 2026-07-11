import SwiftUI

struct RadarChart: View {
    let values: [Double]
    var color: Color = Theme.Chart.strain
    var size: CGFloat = 200

    var body: some View {
        Canvas { ctx, _ in
            let n = values.count
            guard n >= 3 else { return }
            let c = CGPoint(x: size / 2, y: size / 2)
            let r = size / 2 - 16
            func pt(_ i: Int, _ frac: Double) -> CGPoint {
                let a = -CGFloat.pi / 2 + CGFloat(i) / CGFloat(n) * 2 * .pi
                return CGPoint(x: c.x + cos(a) * r * CGFloat(frac), y: c.y + sin(a) * r * CGFloat(frac))
            }
            for g in [0.25, 0.5, 0.75, 1.0] {
                var ring = Path()
                for i in 0...n {
                    let p = pt(i % n, g)
                    if i == 0 { ring.move(to: p) } else { ring.addLine(to: p) }
                }
                ctx.stroke(ring, with: .color(Theme.Colors.separator), style: StrokeStyle(lineWidth: 1))
            }
            for i in 0..<n {
                var ax = Path(); ax.move(to: c); ax.addLine(to: pt(i, 1))
                ctx.stroke(ax, with: .color(Theme.Colors.separator), style: StrokeStyle(lineWidth: 1))
            }
            var poly = Path()
            for i in 0..<n {
                let p = pt(i, min(max(values[i], 0), 1))
                if i == 0 { poly.move(to: p) } else { poly.addLine(to: p) }
            }
            poly.closeSubpath()
            ctx.fill(poly, with: .color(color.opacity(0.25)))
            ctx.stroke(poly, with: .color(color), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
        .frame(width: size, height: size)
    }
}
