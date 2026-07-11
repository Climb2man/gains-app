import SwiftUI

struct WelcomeScreen: View {
    let onGetStarted: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var heroOffset: CGFloat { reduceMotion ? 0 : (appeared ? 0 : 16) }
    private var heroOpacity: Double { reduceMotion ? 1 : (appeared ? 1 : 0) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Theme.Spacing.xl) {
                Spacer(minLength: 0)
                OnboardingHaloMark(size: 128)
                VStack(spacing: Theme.Spacing.md) {
                    Text("Your health, all in one private place")
                        .font(Theme.Font.onboardingTitle)
                        .foregroundStyle(Theme.Colors.label)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Txt(
                        "Track your labs, sleep, recovery, and nutrition: calm, private, and on your phone.",
                        variant: .body, color: .labelSecondary, center: true
                    )
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .offset(y: heroOffset)
            .opacity(heroOpacity)

            VStack(spacing: Theme.Spacing.lg) {
                AppButton(title: "Get Started", kind: .primary, action: onGetStarted)
                Txt(
                    "By continuing, you agree to our Terms & Privacy Policy",
                    variant: .footnote, color: .labelTertiary, center: true
                )
            }
            .opacity(heroOpacity)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(Theme.Motion.stepTransition.delay(0.05)) { appeared = true }
        }
    }
}

#if DEBUG
#Preview("Welcome") {
    WelcomeScreen {}
}
#endif
