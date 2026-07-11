import SwiftUI

struct TypicalRangeBar: View {
    let value: Double
    let rangeLow: Double
    let rangeHigh: Double
    let color: Color
    let label: String
    let pctDisplay: String
    let timeDisplay: String
    var height: CGFloat = 12
    var width: CGFloat = 300
    var animated: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown: Bool = false

    var body: some View {
        let v = clamp01(value)
        let drawnFraction = (animated && !reduceMotion && !grown) ? 0 : v
        let lo = clamp01(min(rangeLow, rangeHigh))
        let hi = clamp01(max(rangeLow, rangeHigh))
        let valueW = CGFloat(drawnFraction) * width
        let bandX = CGFloat(lo) * width
        let bandW = max(0, CGFloat(hi - lo) * width)
        let r = min(Theme.Radius.pill, height / 2)

        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Colors.labelSecondary)
                Text(pctDisplay)
                    .font(Theme.Font.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Colors.label)
                Spacer(minLength: Theme.Spacing.sm)
                Text(timeDisplay)
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Colors.labelTertiary)
            }

            ZStack(alignment: .leading) {
                Canvas { context, _ in
                    let track = Path(roundedRect: CGRect(x: 0, y: 0, width: width, height: height), cornerRadius: r)

                    context.fill(track, with: .color(Theme.Colors.fieldBackground))

                    if bandW > 0 {
                        let bandRect = CGRect(x: bandX, y: 0, width: bandW, height: height)
                        let band = Path(bandRect)
                        context.fill(band, with: .color(color.opacity(0.12)))

                        var hatch = context
                        hatch.clip(to: band)
                        let step: CGFloat = 6
                        var offset = -height
                        var stripes = Path()
                        while bandX + offset < bandX + bandW + height {
                            stripes.move(to: CGPoint(x: bandX + offset, y: height))
                            stripes.addLine(to: CGPoint(x: bandX + offset + height, y: 0))
                            offset += step
                        }
                        hatch.stroke(
                            stripes,
                            with: .color(color.opacity(0.35)),
                            style: StrokeStyle(lineWidth: 2)
                        )
                    }
                }
                .frame(width: width, height: height)

                if valueW > 0 {
                    RoundedRectangle(cornerRadius: r, style: .continuous)
                        .fill(color)
                        .frame(width: valueW, height: height)
                }
            }
            .frame(width: width, height: height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(pctDisplay), \(timeDisplay)")
        .onAppear {
            guard animated, !reduceMotion else { return }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) { grown = true }
        }
    }

    private func clamp01(_ v: Double) -> Double { max(0, min(1, v)) }
}
