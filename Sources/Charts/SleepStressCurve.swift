import SwiftUI

struct SleepStressCurve: View {
    let points: [SleepStressPoint]
    let startLabel: String
    let endLabel: String
    var showMoon: Bool = true
    var height: CGFloat = 180
    var width: CGFloat = 320

    private let vPadding: CGFloat = 12
    private let labelBand: CGFloat = 18
    private let yLabelGutter: CGFloat = 26
    private let scaleMax: Double = 3
    private let gridLevels: [Double] = [3, 2, 1, 0]
    private var teal: Color { Theme.Chart.recovery }

    var body: some View {
        let plotH = height - labelBand
        let plotW = width - yLabelGutter
        let labelY = height - 5
        let windowLeft = yLabelGutter
        let windowRight = width

        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                guard !points.isEmpty else {
                    let midY = plotH / 2
                    var base = Path()
                    base.move(to: CGPoint(x: yLabelGutter, y: midY))
                    base.addLine(to: CGPoint(x: width, y: midY))
                    context.stroke(
                        base,
                        with: .color(Theme.Colors.separator),
                        style: StrokeStyle(lineWidth: 2, dash: [4, 6])
                    )
                    return
                }

                let windowRect = CGRect(
                    x: windowLeft, y: vPadding,
                    width: windowRight - windowLeft, height: plotH - vPadding * 2
                )
                context.fill(Path(windowRect), with: .color(Theme.Colors.fieldBackground.opacity(0.7)))

                for level in gridLevels {
                    let y = levelToY(level, plotH: plotH)
                    var line = Path()
                    line.move(to: CGPoint(x: yLabelGutter, y: y))
                    line.addLine(to: CGPoint(x: width, y: y))
                    context.stroke(
                        line,
                        with: .color(Theme.Colors.separator.opacity(0.7)),
                        style: StrokeStyle(lineWidth: 1)
                    )
                    let text = Text(level, format: .number.precision(.fractionLength(1)))
                        .font(Theme.Font.footnote)
                        .foregroundStyle(Theme.Colors.labelTertiary)
                    context.draw(context.resolve(text), at: CGPoint(x: 0, y: y), anchor: .leading)
                }

                for markerX in [windowLeft, windowRight] {
                    var marker = Path()
                    marker.move(to: CGPoint(x: markerX, y: vPadding))
                    marker.addLine(to: CGPoint(x: markerX, y: plotH - vPadding))
                    context.stroke(
                        marker,
                        with: .color(Theme.Colors.borderStrong),
                        style: StrokeStyle(lineWidth: 1.5, dash: [3, 4])
                    )
                }

                let sampled = points.sorted { $0.x < $1.x }
                let coords = toCoords(sampled, plotW: plotW, plotH: plotH)
                let linePath = ChartCurve.smoothLine(coords)
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
                                .init(color: teal.opacity(0.18), location: 0),
                                .init(color: teal.opacity(0.01), location: 1),
                            ]),
                            startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: plotH)
                        )
                    )
                }
                context.stroke(
                    linePath,
                    with: .color(teal),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                )

                let startText = Text(startLabel).font(Theme.Font.footnote).foregroundStyle(Theme.Colors.labelTertiary)
                context.draw(context.resolve(startText), at: CGPoint(x: windowLeft, y: labelY), anchor: .leading)
                let endText = Text(endLabel).font(Theme.Font.footnote).foregroundStyle(Theme.Colors.labelTertiary)
                context.draw(context.resolve(endText), at: CGPoint(x: windowRight, y: labelY), anchor: .trailing)
            }
            .frame(width: width, height: height)

            if showMoon, !points.isEmpty {
                Image(systemName: "moon.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(teal)
                    .offset(x: windowLeft + 4, y: 2)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: height)
    }

    private func toCoords(_ points: [SleepStressPoint], plotW: CGFloat, plotH: CGFloat) -> [CGPoint] {
        let innerH = plotH - vPadding * 2
        return points.map { p in
            let norm = max(0, min(1, p.level / scaleMax))
            return CGPoint(
                x: yLabelGutter + CGFloat(max(0, min(1, p.x))) * plotW,
                y: vPadding + (1 - CGFloat(norm)) * innerH
            )
        }
    }

    private func levelToY(_ level: Double, plotH: CGFloat) -> CGFloat {
        let innerH = plotH - vPadding * 2
        let norm = max(0, min(1, level / scaleMax))
        return vPadding + (1 - CGFloat(norm)) * innerH
    }
}
