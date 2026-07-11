import SwiftUI

struct Sparkline: View {
    let values: [Double]
    var color: Color = Theme.Chart.calories
    var width: CGFloat = 120
    var height: CGFloat = 44
    var fill: Bool = true

    var body: some View {
        Canvas { ctx, _ in
            guard values.count > 1 else { return }
            let coords = LineGeometry.lineCoords(values, width: width, height: height, vPadding: 4)
            let line = ChartCurve.smoothLine(coords)
            if fill, let f = coords.first, let l = coords.last {
                var area = line
                area.addLine(to: CGPoint(x: l.x, y: height))
                area.addLine(to: CGPoint(x: f.x, y: height))
                area.closeSubpath()
                ctx.fill(area, with: .linearGradient(
                    Gradient(colors: [color.opacity(0.25), color.opacity(0.0)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: height)))
            }
            ctx.stroke(line, with: .color(color),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            if let last = coords.last {
                let r: CGFloat = 3
                ctx.fill(Path(ellipseIn: CGRect(x: last.x - r, y: last.y - r, width: r * 2, height: r * 2)),
                         with: .color(color))
            }
        }
        .frame(width: width, height: height)
    }
}
