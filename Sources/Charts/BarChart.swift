import SwiftUI

struct BarChart: View {
    let values: [Double]
    var labels: [String]?
    var labelCount: Int = 4
    var highlightIndex: Int = -1
    var height: CGFloat = 140
    var width: CGFloat = 300
    var color: Color = Theme.Chart.strain
    var highlightColor: Color = Theme.Colors.tint
    var barColors: [Color?]?
    var gridLines: Int = 4

    private let topPadding: CGFloat = 8
    private let labelBand: CGFloat = 18

    private func barFill(_ i: Int) -> Color {
        if let override = barColors?[safe: i], let c = override { return c }
        return i == highlightIndex ? highlightColor : color
    }

    var body: some View {
        let hasData = !values.isEmpty
        let hasLabels = (labels?.isEmpty == false)
        let labelArray = labels ?? []
        let max = hasData ? (values.max() ?? 0) : 0
        let plotBottom = hasLabels ? height - labelBand : height
        let plotH = plotBottom - topPadding
        let n = values.count
        let slot: CGFloat = n > 0 ? width / CGFloat(n) : width
        let barW = slot * 0.58
        let barRadius = min(Theme.Radius.sm, barW / 2)

        let labelIdx = hasLabels ? ChartAxis.sparseLabelIndices(labelArray, count: labelCount) : []

        VStack(spacing: 0) {
            Canvas { context, _ in
                if gridLines > 0 {
                    for i in 0...gridLines {
                        let y = topPadding + plotH * CGFloat(i) / CGFloat(gridLines)
                        var line = Path()
                        line.move(to: CGPoint(x: 0, y: y))
                        line.addLine(to: CGPoint(x: width, y: y))
                        context.stroke(
                            line,
                            with: .color(Theme.Colors.separator.opacity(0.6)),
                            style: StrokeStyle(lineWidth: 1)
                        )
                    }
                }

                guard hasData, max > 0 else { return }
                for (i, v) in values.enumerated() {
                    let norm = v / max
                    let barH = Swift.max(2, CGFloat(norm) * plotH)
                    let x = CGFloat(i) * slot + (slot - barW) / 2
                    let y = topPadding + (plotH - barH)
                    let rect = CGRect(x: x, y: y, width: barW, height: barH)
                    let bar = Path(roundedRect: rect, cornerRadius: barRadius)
                    context.fill(bar, with: .color(barFill(i)))
                }
            }
            .frame(width: width, height: hasLabels ? height - labelBand : height)

            if hasLabels {
                ZStack(alignment: .topLeading) {
                    ForEach(labelIdx, id: \.self) { idx in
                        let anchor = AxisAnchor.forTick(idx: idx, lastIndex: labelArray.count - 1)
                        Text(labelArray[idx])
                            .font(Theme.Font.footnote)
                            .foregroundStyle(Theme.Colors.labelTertiary)
                            .fixedSize()
                            .modifier(BarLabelPosition(
                                slotCenter: CGFloat(idx) * slot + slot / 2,
                                width: width,
                                anchor: anchor
                            ))
                    }
                }
                .frame(width: width, height: labelBand, alignment: .topLeading)
            }
        }
        .frame(width: width)
    }
}

private struct BarLabelPosition: ViewModifier {
    let slotCenter: CGFloat
    let width: CGFloat
    let anchor: AxisAnchor

    func body(content: Content) -> some View {
        switch anchor {
        case .start:
            content.frame(width: width, alignment: .leading)
        case .end:
            content.frame(width: width, alignment: .trailing)
        case .middle:
            content
                .frame(width: width, alignment: .leading)
                .offset(x: slotCenter)
                .alignmentGuide(.leading) { d in d.width / 2 }
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
