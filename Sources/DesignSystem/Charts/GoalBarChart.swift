import SwiftUI

struct GoalBarChart: View {
    let values: [Double]
    let goal: Double
    var color: Color = Theme.Chart.strain
    var width: CGFloat = 300
    var height: CGFloat = 140

    var body: some View {
        let maxV = max(goal, values.max() ?? 1) * 1.1
        Canvas { ctx, _ in
            func y(_ v: Double) -> CGFloat { height - CGFloat(v / maxV) * height }
            let n = max(values.count, 1)
            let slot = width / CGFloat(n)
            let bw = min(slot * 0.55, 22)
            for (i, v) in values.enumerated() {
                let x = slot * CGFloat(i) + (slot - bw) / 2
                let top = y(v)
                let rect = CGRect(x: x, y: top, width: bw, height: height - top)
                ctx.fill(Path(roundedRect: rect, cornerRadius: bw / 2),
                         with: .color(v >= goal ? color : color.opacity(0.30)))
            }
            let gy = y(goal)
            var gl = Path()
            gl.move(to: CGPoint(x: 0, y: gy))
            gl.addLine(to: CGPoint(x: width, y: gy))
            ctx.stroke(gl, with: .color(Theme.Colors.label),
                       style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
        }
        .frame(width: width, height: height)
    }
}
