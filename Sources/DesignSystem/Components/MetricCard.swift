import SwiftUI

struct MetricCard: View {
    enum Trend { case up, down, none }

    let icon: String
    let title: String
    let value: String
    var unit: String? = nil
    var trend: Trend = .none
    var trendColor: Color = Theme.Colors.tint
    var status: String? = nil
    var statusColor: Color = Theme.Colors.labelSecondary
    var accent: Color = Theme.Colors.labelSecondary
    var glass: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
                Text(title)
                    .font(Theme.Font.subhead.weight(.medium))
                    .foregroundStyle(Theme.Colors.labelSecondary)
                Spacer(minLength: 0)
                if trend != .none {
                    Image(systemName: trend == .up ? "arrow.up" : "arrow.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(trendColor)
                        .padding(5)
                        .background(Circle().fill(trendColor.opacity(0.15)))
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(Theme.Font.metricNumber)
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .foregroundStyle(Theme.Colors.label)
                if let unit {
                    Text(unit)
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.Colors.labelSecondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            if let status {
                Text(status)
                    .font(Theme.Font.footnote.weight(.medium))
                    .foregroundStyle(statusColor)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .cardShadow()
    }

    @ViewBuilder
    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card)
        if glass {
            Color.clear.gainsGlassChrome(in: shape)
        } else {
            shape.fill(Theme.Colors.surface)
        }
    }
}

struct FloatingStatCard: View {
    var icon: String? = nil
    let title: String
    let value: String
    var unit: String? = nil
    var trend: MetricCard.Trend = .none
    let trendColor: Color
    let accent: Color
    var glass: Bool = false

    var body: some View {
        MetricCard(
            icon: icon ?? "circle.dashed",
            title: title,
            value: value,
            unit: unit,
            trend: trend,
            trendColor: trendColor,
            accent: accent,
            glass: glass
        )
    }
}

#if DEBUG
#Preview {
    VStack(spacing: Theme.Spacing.md) {
        HStack(spacing: Theme.Spacing.md) {
            MetricCard(icon: "waveform.path.ecg", title: "Resting HRV", value: "85", unit: "ms",
                            trend: .up, trendColor: Theme.Colors.tint,
                            status: "vs your typical", accent: Theme.Chart.recovery)
            MetricCard(icon: "heart.fill", title: "Resting HR", value: "59", unit: "bpm",
                            trend: .down, trendColor: Theme.Chart.calories,
                            accent: Theme.Chart.heartrate)
        }

        HStack(spacing: Theme.Spacing.md) {
            FloatingStatCard(icon: "moon.fill", title: "Sleep", value: "7.4", unit: "h",
                             trend: .up, trendColor: Theme.Colors.tint, accent: Theme.Chart.sleep)
            FloatingStatCard(title: "Strain", value: "12.6",
                             trendColor: Theme.Colors.tint, accent: Theme.Chart.strain)
        }
    }
    .padding()
    .background(Theme.Colors.background)
}

#Preview("Glass (hero layer)") {
    ZStack {
        Theme.Chart.heroGradient(forRecovery: 78).ignoresSafeArea()
        HStack(spacing: Theme.Spacing.md) {
            FloatingStatCard(icon: "bolt.heart.fill", title: "Recovery", value: "78", unit: "%",
                             trend: .up, trendColor: Theme.Colors.onTint,
                             accent: Theme.Colors.onTint, glass: true)
            FloatingStatCard(icon: "waveform.path.ecg", title: "HRV", value: "92", unit: "ms",
                             trendColor: Theme.Colors.onTint,
                             accent: Theme.Colors.onTint, glass: true)
        }
        .padding()
    }
}
#endif
