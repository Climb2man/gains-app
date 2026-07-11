import SwiftUI

struct DonutSegment: Identifiable {
    let value: Double
    let color: Color
    var label: String?
    var id: String { label ?? "\(value)-\(color.hashValue)" }

    init(value: Double, color: Color, label: String? = nil) {
        self.value = value
        self.color = color
        self.label = label
    }
}

struct DonutChart: View {
    let segments: [DonutSegment]
    var size: CGFloat = 160
    var strokeWidth: CGFloat = 18
    var centerLabel: String?
    var centerSubLabel: String?

    private let gapDegrees: Double = 4

    var body: some View {
        ZStack {
            Canvas { context, canvasSize in
                let dim = min(canvasSize.width, canvasSize.height)
                let radius = (dim - strokeWidth) / 2
                let centerPt = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                guard radius > 0 else { return }

                var track = Path()
                track.addEllipse(in: CGRect(
                    x: centerPt.x - radius, y: centerPt.y - radius,
                    width: radius * 2, height: radius * 2
                ))
                context.stroke(
                    track,
                    with: .color(Theme.Colors.fieldBackground),
                    style: StrokeStyle(lineWidth: strokeWidth)
                )

                let drawable = segments.filter { $0.value > 0 }
                let total = drawable.reduce(0) { $0 + $1.value }
                guard !drawable.isEmpty, total > 0 else { return }

                let gapCount = Double(drawable.count)
                let gapFraction = gapDegrees / 360
                let totalGap = gapCount * gapFraction
                let arcSpan = max(0, 1 - totalGap)

                var cursor = 0.0
                for seg in drawable {
                    let fraction = seg.value / total
                    let arcFraction = fraction * arcSpan
                    let startAngle = -90.0 + cursor * 360
                    let endAngle = startAngle + arcFraction * 360
                    var arc = Path()
                    arc.addArc(
                        center: centerPt,
                        radius: radius,
                        startAngle: .degrees(startAngle),
                        endAngle: .degrees(endAngle),
                        clockwise: false
                    )
                    context.stroke(
                        arc,
                        with: .color(seg.color),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )
                    cursor += arcFraction + gapFraction
                }
            }

            if centerLabel != nil || centerSubLabel != nil {
                VStack(spacing: Theme.Spacing.xs) {
                    if let centerLabel {
                        Text(centerLabel)
                            .font(Theme.Font.title2)
                            .foregroundStyle(Theme.Colors.label)
                            .multilineTextAlignment(.center)
                    }
                    if let centerSubLabel {
                        Text(centerSubLabel)
                            .font(Theme.Font.footnote)
                            .foregroundStyle(Theme.Colors.labelSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
        .frame(width: size, height: size)
    }
}
