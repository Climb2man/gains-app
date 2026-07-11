import SwiftUI

struct OnboardingHaloMark: View {
    /// The overall diameter of the halo ring. The inner app disc scales from this.
    var size: CGFloat = 120

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var swept = false

    /// Ring thickness scales with the mark so it reads at any size.
    private var lineWidth: CGFloat { size * 0.06 }
    /// The app disc sits inside the ring with a comfortable inset.
    private var discSize: CGFloat { size * 0.62 }
    /// The leaf glyph fills most of the disc.
    private var glyphSize: CGFloat { discSize * 0.46 }
    /// How far the ring has swept in (0 → 1). Instant + complete under Reduce Motion.
    private var drawn: Double { reduceMotion ? 1 : (swept ? 1 : 0) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.Colors.tint.opacity(0.08),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            Circle()
                .trim(from: 0, to: max(0.0001, drawn))
                .stroke(
                    AngularGradient(
                        colors: Theme.Chart.gradientStops(for: Theme.Colors.tint),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Image(systemName: "leaf.fill")
                .font(.system(size: glyphSize, weight: .semibold))
                .foregroundStyle(Theme.Colors.onTint)
                .frame(width: discSize, height: discSize)
                .background(Theme.Colors.tint, in: Circle())
                .cardShadow(Theme.Shadow.tinted(Theme.Colors.tint))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(Theme.Motion.stepTransition) { swept = true }
        }
    }
}

#if DEBUG
#Preview("OnboardingHaloMark") {
    VStack(spacing: Theme.Spacing.xxl) {
        OnboardingHaloMark()
        OnboardingHaloMark(size: 80)
    }
    .padding(Theme.Spacing.xxl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.Colors.background)
}
#endif
