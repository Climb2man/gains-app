import SwiftUI

struct SegmentedBar: View {
    struct Segment: Identifiable {
        let label: String
        let value: Double
        let color: Color
        var id: String { label }
    }

    let segments: [Segment]
    var height: CGFloat = 12
    var showLegend: Bool = true
    var formatValue: ((Double) -> String)?

    private var drawable: [Segment] { segments.filter { $0.value > 0 } }
    private var total: Double { drawable.reduce(0) { $0 + $1.value } }
    private var hasData: Bool { total > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            GeometryReader { geo in
                let gap: CGFloat = hasData ? 2 : 0
                let gapTotal = gap * CGFloat(max(0, drawable.count - 1))
                let usable = max(0, geo.size.width - gapTotal)
                HStack(spacing: gap) {
                    ForEach(drawable) { seg in
                        Rectangle()
                            .fill(seg.color)
                            .frame(width: total > 0 ? usable * (seg.value / total) : 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: height)
            .background(Theme.Colors.fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous))

            if showLegend {
                FlowLayout(spacing: Theme.Spacing.lg) {
                    ForEach(segments) { seg in
                        HStack(spacing: Theme.Spacing.sm) {
                            Circle()
                                .fill(seg.color)
                                .frame(width: 8, height: 8)
                            Txt(seg.label, variant: .footnote, color: .labelSecondary)
                            Text(formatValue?(seg.value) ?? Format.oneDecimal(seg.value))
                                .font(Theme.Font.footnote.weight(.semibold))
                                .foregroundStyle(Theme.Colors.label)
                        }
                    }
                }
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width - bounds.minX > maxWidth {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
