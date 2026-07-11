import SwiftUI

struct SleepStagesChart: View {
    let stages: [Int]
    var colors: [Color] = [Theme.Chart.calories, Theme.Chart.strain, Theme.Chart.recovery, Theme.Chart.sleep]
    var width: CGFloat = 320
    var height: CGFloat = 150

    var body: some View {
        let levels = colors.count
        Canvas { ctx, _ in
            let n = stages.count
            guard n > 0 else { return }
            let slot = width / CGFloat(n)
            let bandH = height / CGFloat(levels)
            for (i, s) in stages.enumerated() {
                let lvl = min(max(s, 0), levels - 1)
                let rect = CGRect(x: CGFloat(i) * slot, y: CGFloat(lvl) * bandH,
                                  width: slot + 0.5, height: bandH - 2)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(colors[lvl]))
            }
        }
        .frame(width: width, height: height)
    }
}
