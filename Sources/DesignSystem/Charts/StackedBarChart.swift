import SwiftUI

struct StackedBarChart: View {
    let bars: [[Double]]
    var colors: [Color] = [Theme.Chart.recovery, Theme.Chart.strain, Theme.Chart.sleep, Theme.Chart.calories]
    var width: CGFloat = 300
    var height: CGFloat = 150

    var body: some View {
        let totals = bars.map { $0.reduce(0, +) }
        let maxV = max(totals.max() ?? 1, 1)
        Canvas { ctx, _ in
            let n = max(bars.count, 1)
            let slot = width / CGFloat(n)
            let bw = min(slot * 0.6, 26)
            for (i, segs) in bars.enumerated() {
                var yTop = height
                let x = slot * CGFloat(i) + (slot - bw) / 2
                for (j, v) in segs.enumerated() {
                    let h = CGFloat(v / maxV) * height
                    let rect = CGRect(x: x, y: yTop - h, width: bw, height: h)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(colors[j % colors.count]))
                    yTop -= h
                }
            }
        }
        .frame(width: width, height: height)
    }
}
