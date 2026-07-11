import SwiftUI

enum LineGeometry {
    static func valueBounds(_ values: [Double], extra: Double? = nil) -> (min: Double, max: Double) {
        let all = extra != nil ? values + [extra!] : values
        guard let lo = all.min(), let hi = all.max() else { return (0, 1) }
        return (lo, hi)
    }

    static func valueToY(
        _ v: Double, min: Double, max: Double, height: CGFloat, vPadding: CGFloat
    ) -> CGFloat {
        let range = max - min
        let innerH = height - vPadding * 2
        let norm = range == 0 ? 0.5 : (v - min) / range
        return vPadding + (1 - CGFloat(norm)) * innerH
    }

    static func lineCoords(
        _ values: [Double], width: CGFloat, height: CGFloat, vPadding: CGFloat, extra: Double? = nil
    ) -> [CGPoint] {
        let n = values.count
        let bounds = valueBounds(values, extra: extra)
        let stepX = n > 1 ? width / CGFloat(n - 1) : 0
        return values.enumerated().map { i, v in
            CGPoint(
                x: n > 1 ? CGFloat(i) * stepX : width / 2,
                y: valueToY(v, min: bounds.min, max: bounds.max, height: height, vPadding: vPadding)
            )
        }
    }
}

struct ChartAxisLabels: View {
    let indices: [Int]
    let lastIndex: Int
    let width: CGFloat
    let band: CGFloat
    let text: (Int) -> String
    let x: (Int) -> CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(indices, id: \.self) { idx in
                let anchor = AxisAnchor.forTick(idx: idx, lastIndex: lastIndex)
                Text(text(idx))
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Colors.labelTertiary)
                    .fixedSize()
                    .modifier(AxisTickPosition(tickX: x(idx), width: width, anchor: anchor))
            }
        }
        .frame(width: width, height: band, alignment: .topLeading)
    }
}

private struct AxisTickPosition: ViewModifier {
    let tickX: CGFloat
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
                .offset(x: tickX)
                .alignmentGuide(.leading) { d in d.width / 2 }
        }
    }
}
