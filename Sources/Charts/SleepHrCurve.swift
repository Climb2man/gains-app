import SwiftUI

struct SleepHrCurve: View {
    let points: [SleepHrPoint]
    let startLabel: String
    let endLabel: String
    var height: CGFloat = 180
    var width: CGFloat = 320

    private let vPadding: CGFloat = 10
    private let labelBand: CGFloat = 18
    private let yLabelGutter: CGFloat = 26
    private let gridBpm: [Double] = [90, 70, 50, 30]
    private let maxPoints = 400
    private var sleepBlue: Color { Theme.Chart.strain }

    var body: some View {
        let plotH = height - labelBand
        let plotW = width - yLabelGutter
        let labelY = height - 5
        let startX = yLabelGutter
        let endX = width

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

            let sampled = downsample(points).sorted { $0.x < $1.x }
            let bpms = sampled.map(\.bpm)
            let dataMin = bpms.min() ?? 0
            let dataMax = bpms.max() ?? 0
            let minB = Swift.min(dataMin, gridBpm.last ?? 30)
            let maxB = Swift.max(dataMax, gridBpm.first ?? 90)

            for bpm in gridBpm {
                let y = bpmToY(bpm, min: minB, max: maxB, plotH: plotH)
                var line = Path()
                line.move(to: CGPoint(x: yLabelGutter, y: y))
                line.addLine(to: CGPoint(x: width, y: y))
                context.stroke(
                    line,
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: Theme.Colors.separator.opacity(0.3), location: 0),
                            .init(color: Theme.Colors.separator.opacity(0.9), location: 0.12),
                            .init(color: Theme.Colors.separator.opacity(0.9), location: 1),
                        ]),
                        startPoint: CGPoint(x: 0, y: y), endPoint: CGPoint(x: width, y: y)
                    ),
                    style: StrokeStyle(lineWidth: 1)
                )
                let text = Text(bpm, format: .number.precision(.fractionLength(0)))
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Colors.labelTertiary)
                context.draw(context.resolve(text), at: CGPoint(x: 0, y: y), anchor: .leading)
            }

            for markerX in [startX, endX] {
                var marker = Path()
                marker.move(to: CGPoint(x: markerX, y: vPadding))
                marker.addLine(to: CGPoint(x: markerX, y: plotH - vPadding))
                context.stroke(
                    marker,
                    with: .color(Theme.Colors.borderStrong),
                    style: StrokeStyle(lineWidth: 1.5, dash: [3, 4])
                )
            }

            let coords = toCoords(sampled, plotW: plotW, plotH: plotH, min: minB, max: maxB)
            context.stroke(
                ChartCurve.smoothLine(coords),
                with: .color(sleepBlue),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )

            let startText = Text(startLabel).font(Theme.Font.footnote).foregroundStyle(Theme.Colors.labelTertiary)
            context.draw(context.resolve(startText), at: CGPoint(x: startX, y: labelY), anchor: .leading)
            let endText = Text(endLabel).font(Theme.Font.footnote).foregroundStyle(Theme.Colors.labelTertiary)
            context.draw(context.resolve(endText), at: CGPoint(x: endX, y: labelY), anchor: .trailing)
        }
        .frame(width: width, height: height)
    }

    private func downsample(_ points: [SleepHrPoint]) -> [SleepHrPoint] {
        guard points.count > maxPoints else { return points }
        let stride = Int(ceil(Double(points.count) / Double(maxPoints)))
        var out: [SleepHrPoint] = []
        var i = 0
        while i < points.count {
            out.append(points[i])
            i += stride
        }
        if let last = points.last, out.last?.x != last.x { out.append(last) }
        return out
    }

    private func toCoords(
        _ points: [SleepHrPoint], plotW: CGFloat, plotH: CGFloat, min: Double, max: Double
    ) -> [CGPoint] {
        let range = max - min
        let innerH = plotH - vPadding * 2
        return points.map { p in
            let norm = range == 0 ? 0.5 : (p.bpm - min) / range
            return CGPoint(
                x: yLabelGutter + CGFloat(Swift.max(0, Swift.min(1, p.x))) * plotW,
                y: vPadding + (1 - CGFloat(norm)) * innerH
            )
        }
    }

    private func bpmToY(_ bpm: Double, min: Double, max: Double, plotH: CGFloat) -> CGFloat {
        let range = max - min
        let innerH = plotH - vPadding * 2
        let norm = range == 0 ? 0.5 : (bpm - min) / range
        return vPadding + (1 - CGFloat(norm)) * innerH
    }
}
