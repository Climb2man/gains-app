import SwiftUI

struct MacroDonut: View {
    /// One slice: value (relative weight), base color, and label.
    struct Segment: Identifiable {
        let value: Double
        let color: Color
        let label: String
        var id: String { label }
    }

    let segments: [Segment]
    var size: CGFloat = 132
    var strokeWidth: CGFloat = 16
    var centerLabel: String?
    var centerSubLabel: String?
    /// Sweep slices in on appear (staggered). Static when false or Reduce Motion is on.
    var animated: Bool = true

    /// Tuple-based init for concise call sites.
    init(
        segments: [(value: Double, color: Color, label: String)],
        size: CGFloat = 132,
        strokeWidth: CGFloat = 16,
        centerLabel: String? = nil,
        centerSubLabel: String? = nil,
        animated: Bool = true
    ) {
        self.segments = segments.map { Segment(value: $0.value, color: $0.color, label: $0.label) }
        self.size = size
        self.strokeWidth = strokeWidth
        self.centerLabel = centerLabel
        self.centerSubLabel = centerSubLabel
        self.animated = animated
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private let gapFraction: Double = 4.0 / 360.0

    /// Only positive-value slices contribute to the ring.
    private var drawable: [Segment] { segments.filter { $0.value > 0 } }
    private var total: Double { drawable.reduce(0) { $0 + $1.value } }

    /// Ring fraction left for arcs after subtracting one gap per drawn slice.
    private var arcSpan: Double { max(0, 1 - Double(drawable.count) * gapFraction) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.Colors.labelTertiary.opacity(0.10), style: strokeStyle)

            ForEach(Array(arcs.enumerated()), id: \.element.segment.id) { index, arc in
                Circle()
                    .trim(from: arc.start, to: drawnEnd(arc, index: index))
                    .stroke(Theme.Chart.ringGradient(for: arc.segment.color), style: strokeStyle)
                    .rotationEffect(.degrees(-90))
            }

            center
        }
        .frame(width: size, height: size)
        .onAppear {
            guard animated, !reduceMotion else { shown = true; return }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) { shown = true }
        }
    }

    private struct Arc { let segment: Segment; let start: Double; let end: Double }

    private var arcs: [Arc] {
        guard total > 0 else { return [] }
        var cursor = 0.0
        var result: [Arc] = []
        for seg in drawable {
            let fraction = (seg.value / total) * arcSpan
            result.append(Arc(segment: seg, start: cursor, end: cursor + fraction))
            cursor += fraction + gapFraction
        }
        return result
    }

    /// Animated trailing edge: sits at `start` until shown, then springs to `end`.
    /// Slices share one spring but each keeps its own window, so they fill in order.
    private func drawnEnd(_ arc: Arc, index: Int) -> Double {
        guard animated, !reduceMotion else { return arc.end }
        return shown ? arc.end : arc.start
    }

    private var strokeStyle: StrokeStyle { StrokeStyle(lineWidth: strokeWidth, lineCap: .round) }

    @ViewBuilder
    private var center: some View {
        if centerLabel != nil || centerSubLabel != nil {
            VStack(spacing: 2) {
                if let centerLabel {
                    Text(centerLabel)
                        .font(Theme.Font.metricNumber)
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .foregroundStyle(Theme.Colors.label)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                if let centerSubLabel {
                    Text(centerSubLabel)
                        .font(Theme.Font.footnote)
                        .foregroundStyle(Theme.Colors.labelSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: size - strokeWidth * 2.6)
            .accessibilityHidden(true)
        }
    }
}

#if DEBUG
#Preview("MacroDonut") {
    HStack(spacing: Theme.Spacing.xl) {
        MacroDonut(
            segments: [
                (value: 528, color: Theme.Chart.protein, label: "Protein"),
                (value: 720, color: Theme.Chart.carbs, label: "Carbs"),
                (value: 549, color: Theme.Chart.fat, label: "Fat"),
            ],
            size: 132, strokeWidth: 16,
            centerLabel: "1,840", centerSubLabel: "kcal"
        )
        MacroDonut(
            segments: [],
            size: 92, strokeWidth: 12,
            centerLabel: "–", centerSubLabel: "log a meal"
        )
    }
    .padding(Theme.Spacing.xl)
    .background(Theme.Colors.background)
}
#endif
