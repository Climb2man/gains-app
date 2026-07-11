import SwiftUI

struct RingChart<Center: View>: View {
    let progress: Double
    var size: CGFloat = 160
    var strokeWidth: CGFloat = 16
    var color: Color = Theme.Colors.tint
    var glow: Bool = false
    var heroTrack: Bool = false
    var arcGradient: AngularGradient? = nil
    @ViewBuilder var center: () -> Center

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedProgress: Double = 0

    private var clampedProgress: Double { min(1, max(0, progress)) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(heroTrack ? Theme.Chart.heroTrack : Theme.Chart.ringTrack(for: color), style: trackStyle)

            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(arcGradient ?? Theme.Chart.ringGradient(for: color), style: arcStyle)
                .rotationEffect(.degrees(-90))

            if glow, animatedProgress > 0.001 {
                glowDot
            }

            center()
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onAppear { applyProgress(animate: !reduceMotion) }
        .onChange(of: clampedProgress) { _, _ in applyProgress(animate: false) }
    }

    private var arcRadius: CGFloat { (size - strokeWidth) / 2 }
    private var endpointAngle: Angle { .degrees(-90 + 360 * animatedProgress) }
    private var endpointOffset: CGSize {
        let radians = endpointAngle.radians
        let r = Double(arcRadius)
        return CGSize(width: cos(radians) * r, height: sin(radians) * r)
    }

    private var trackStyle: StrokeStyle { StrokeStyle(lineWidth: strokeWidth) }
    private var arcStyle: StrokeStyle { StrokeStyle(lineWidth: strokeWidth, lineCap: .round) }

    private var glowDot: some View {
        let dot = strokeWidth * 0.62
        return ZStack {
            Circle()
                .fill(color)
                .frame(width: dot * 1.7, height: dot * 1.7)
                .blur(radius: dot * 0.7)
                .opacity(0.55)
            Circle()
                .fill(Theme.Chart.light(color))
                .frame(width: dot, height: dot)
        }
        .offset(endpointOffset)
    }

    private func applyProgress(animate: Bool) {
        if animate {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                animatedProgress = clampedProgress
            }
        } else {
            animatedProgress = clampedProgress
        }
    }
}

extension RingChart where Center == RingCenterLabel {
    init(
        progress: Double,
        size: CGFloat = 160,
        strokeWidth: CGFloat = 16,
        color: Color = Theme.Colors.tint,
        glow: Bool = false,
        centerLabel: String? = nil,
        centerSubLabel: String? = nil
    ) {
        self.init(
            progress: progress,
            size: size,
            strokeWidth: strokeWidth,
            color: color,
            glow: glow,
            center: { RingCenterLabel(label: centerLabel, subLabel: centerSubLabel) }
        )
    }
}

extension RingChart where Center == HeroRingCenter {
    /// The Overview hero recovery ring. `recoveryPct` (0–100) drives the arc length; the arc uses
    /// a fixed white gradient.
    static func hero(recoveryPct: Double) -> RingChart<HeroRingCenter> {
        RingChart<HeroRingCenter>(
            progress: recoveryPct / 100,
            size: 228,
            strokeWidth: 18,
            color: Theme.Chart.recovery,
            glow: false,
            heroTrack: true,
            arcGradient: AngularGradient(
                colors: [Color.white, Color.white.opacity(0.8)],
                center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)
            ),
            center: { HeroRingCenter(pct: recoveryPct) }
        )
    }
}

struct HeroRingCenter: View {
    let pct: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 2) {
            Text("\(Int(pct.rounded()))%")
                .font(Theme.Font.heroNumber)
                .foregroundStyle(Theme.Colors.onTint)
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())
            Text("recovered")
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.Colors.onTint.opacity(0.85))
        }
    }
}

struct RingCenterLabel: View {
    let label: String?
    let subLabel: String?

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if let label {
                Text(label)
                    .font(Theme.Font.title1)
                    .foregroundStyle(Theme.Colors.label)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .multilineTextAlignment(.center)
            }
            if let subLabel {
                Text(subLabel)
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Colors.labelSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

#Preview("Ring · hero + pillars") {
    VStack(spacing: 32) {
        RingChart(progress: 0.72, size: 160, strokeWidth: 16, color: Theme.Chart.recovery, glow: true,
                  centerLabel: "72%", centerSubLabel: "recovery")
        HStack(spacing: 24) {
            RingChart(progress: 0.88, size: 92, strokeWidth: 10, color: Theme.Chart.sleep,
                      centerLabel: "88%")
            RingChart(progress: 0.45, size: 92, strokeWidth: 10, color: Theme.Chart.strain,
                      centerLabel: "45%")
            RingChart(progress: 0.33, size: 92, strokeWidth: 10, color: Theme.Chart.calories,
                      centerLabel: "33%")
        }
    }
    .padding(40)
    .background(Theme.Colors.background)
}
