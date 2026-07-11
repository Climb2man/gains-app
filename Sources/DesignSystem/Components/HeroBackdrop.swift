import SwiftUI

struct HeroBackdrop<Content: View>: View {
    /// The user's own recovery %, 0–100. Drives the gradient ramp so the backdrop echoes the hero number.
    let recoveryPct: Double
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.card + Theme.Spacing.sm, style: .continuous)
    }

    var body: some View {
        content
            .background {
                ZStack {
                    Theme.Chart.heroGradient(forRecovery: recoveryPct)
                    LinearGradient(
                        colors: [Color.black.opacity(0.06), Color.black.opacity(0.16)],
                        startPoint: .top, endPoint: .bottom
                    )
                }
                .animation(reduceMotion ? nil : Theme.Motion.stepTransition, value: recoveryPct)
            }
            .clipShape(shape)
            .overlay { shape.stroke(Color.white.opacity(0.12), lineWidth: 1) }
    }
}

#if DEBUG
#Preview("HeroBackdrop") {
    VStack(spacing: Theme.Spacing.xl) {
        HeroBackdrop(recoveryPct: 94) {
            VStack(spacing: Theme.Spacing.sm) {
                Text("94%").font(Theme.Font.heroNumber).foregroundStyle(Theme.Colors.onTint)
                Text("recovered").font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Colors.onTint.opacity(0.85))
            }
            .frame(maxWidth: .infinity)
            .padding(Theme.Spacing.xxl)
        }
        HeroBackdrop(recoveryPct: 48) {
            Text("48%").font(Theme.Font.heroNumber).foregroundStyle(Theme.Colors.onTint)
                .frame(maxWidth: .infinity).padding(Theme.Spacing.xxl)
        }
    }
    .padding(Theme.Spacing.lg)
    .background(Theme.Colors.background)
}
#endif
