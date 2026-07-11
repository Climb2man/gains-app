import SwiftUI

struct BaselineDeviationChart: View {
    let values: [Double]
    var positiveColor: Color = Theme.Chart.activity
    var negativeColor: Color = Theme.Chart.calories
    var width: CGFloat = 300
    var height: CGFloat = 140

    var body: some View {
        let maxAbs = max(1, values.map { abs($0) }.max() ?? 1)
        Canvas { ctx, _ in
            let mid = height / 2
            var base = Path()
            base.move(to: CGPoint(x: 0, y: mid))
            base.addLine(to: CGPoint(x: width, y: mid))
            ctx.stroke(base, with: .color(Theme.Colors.borderStrong),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

            let n = max(values.count, 1)
            let slot = width / CGFloat(n)
            let bw = min(slot * 0.5, 14)
            for (i, v) in values.enumerated() {
                let cx = slot * CGFloat(i) + slot / 2
                let h = CGFloat(abs(v) / maxAbs) * (mid - 6)
                let rect = v >= 0
                    ? CGRect(x: cx - bw / 2, y: mid - h, width: bw, height: h)
                    : CGRect(x: cx - bw / 2, y: mid, width: bw, height: h)
                ctx.fill(Path(roundedRect: rect, cornerRadius: bw / 2),
                         with: .color(v >= 0 ? positiveColor : negativeColor))
            }
        }
        .frame(width: width, height: height)
    }
}
