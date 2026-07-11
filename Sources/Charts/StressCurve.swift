import SwiftUI

struct StressCurve: View {
    let points: [StressGraphPoint]
    var maxValue: Double? = nil
    var height: CGFloat = 160
    var width: CGFloat = 300
    var showLastPoint: Bool = true
    var labelCount: Int = 4

    private let vPadding: CGFloat = 10
    private let labelBand: CGFloat = 18

    private var rampLow: Color { Theme.Colors.success }
    private var rampMid: Color { Theme.Colors.warning }
    private var rampHigh: Color { Theme.Colors.danger }

    var body: some View {
        let hasData = !points.isEmpty
        let plotH = height - labelBand

        VStack(spacing: 0) {
            Canvas { context, _ in
                guard hasData, points.count > 1 else {
                    let midY = plotH / 2
                    var base = Path()
                    base.move(to: CGPoint(x: 0, y: midY))
                    base.addLine(to: CGPoint(x: width, y: midY))
                    context.stroke(
                        base,
                        with: .color(Theme.Colors.separator),
                        style: StrokeStyle(lineWidth: 2, dash: [4, 6])
                    )
                    if hasData {
                        let dot = Path(ellipseIn: CGRect(x: width / 2 - 4, y: midY - 4, width: 8, height: 8))
                        context.fill(dot, with: .color(rampLow))
                    }
                    return
                }

                let values = points.map(\.value)
                let scaleMax = (maxValue.map { $0 > 0 ? $0 : 1 }) ?? Swift.max(values.max() ?? 1, 1)
                let coords = coords(values, scaleMax: scaleMax, plotH: plotH)
                let linePath = ChartCurve.smoothLine(coords)

                let rampStart = CGPoint(x: 0, y: 0)
                let rampEnd = CGPoint(x: 0, y: plotH)

                if let first = coords.first, let last = coords.last {
                    let baseY = plotH - vPadding / 2
                    var area = linePath
                    area.addLine(to: CGPoint(x: last.x, y: baseY))
                    area.addLine(to: CGPoint(x: first.x, y: baseY))
                    area.closeSubpath()
                    context.fill(
                        area,
                        with: .linearGradient(
                            Gradient(stops: [
                                .init(color: rampHigh.opacity(0.22), location: 0),
                                .init(color: rampMid.opacity(0.14), location: 0.5),
                                .init(color: rampLow.opacity(0.02), location: 1),
                            ]),
                            startPoint: rampStart, endPoint: rampEnd
                        )
                    )
                }

                context.stroke(
                    linePath,
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: rampHigh, location: 0),
                            .init(color: rampMid, location: 0.5),
                            .init(color: rampLow, location: 1),
                        ]),
                        startPoint: rampStart, endPoint: rampEnd
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )

                if showLastPoint, let last = coords.last {
                    let halo = Path(ellipseIn: CGRect(x: last.x - 5.5, y: last.y - 5.5, width: 11, height: 11))
                    context.fill(halo, with: .color(Theme.Colors.surface))
                    let core = Path(ellipseIn: CGRect(x: last.x - 3.5, y: last.y - 3.5, width: 7, height: 7))
                    context.fill(core, with: .color(rampColor(atY: last.y, plotH: plotH)))
                }
            }
            .frame(width: width, height: plotH)

            if hasData, points.count > 1 {
                let idxs = ChartAxis.sparseIndices(points.count, count: labelCount)
                let scaleMax = (maxValue.map { $0 > 0 ? $0 : 1 }) ?? Swift.max(points.map(\.value).max() ?? 1, 1)
                let coords = coords(points.map(\.value), scaleMax: scaleMax, plotH: plotH)
                ChartAxisLabels(
                    indices: idxs,
                    lastIndex: points.count - 1,
                    width: width,
                    band: labelBand,
                    text: { points[$0].time },
                    x: { coords[safe: $0]?.x ?? 0 }
                )
            }
        }
        .frame(width: width)
    }

    private func coords(_ values: [Double], scaleMax: Double, plotH: CGFloat) -> [CGPoint] {
        let n = values.count
        let stepX = n > 1 ? width / CGFloat(n - 1) : 0
        let innerH = plotH - vPadding * 2
        return values.enumerated().map { i, v in
            let norm = scaleMax > 0 ? Swift.max(0, Swift.min(1, v / scaleMax)) : 0.5
            return CGPoint(
                x: n > 1 ? CGFloat(i) * stepX : width / 2,
                y: vPadding + (1 - CGFloat(norm)) * innerH
            )
        }
    }

    private func rampColor(atY y: CGFloat, plotH: CGFloat) -> Color {
        let t = Swift.max(0, Swift.min(1, y / Swift.max(1, plotH)))
        if t < 0.5 {
            return mix(rampHigh, rampMid, fraction: t / 0.5)
        }
        return mix(rampMid, rampLow, fraction: (t - 0.5) / 0.5)
    }

    private func mix(_ a: Color, _ b: Color, fraction: CGFloat) -> Color {
        let f = Swift.max(0, Swift.min(1, fraction))
        let ca = a.resolveRGB()
        let cb = b.resolveRGB()
        return Color(
            .sRGB,
            red: Double(ca.r + (cb.r - ca.r) * f),
            green: Double(ca.g + (cb.g - ca.g) * f),
            blue: Double(ca.b + (cb.b - ca.b) * f),
            opacity: 1
        )
    }
}

private extension Color {
    func resolveRGB() -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
        #else
        return (0.5, 0.5, 0.5)
        #endif
    }
}
