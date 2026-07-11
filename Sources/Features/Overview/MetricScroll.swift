import SwiftUI

struct MetricScroll: View {
    let items: [OverviewMetric]
    private let cardWidth: CGFloat = 168
    private let cardHeight: CGFloat = 158

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                ForEach(items) { item in
                    MetricSparkCard(item: item)
                        .frame(width: cardWidth, height: cardHeight)
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, Theme.Spacing.xs)
        }
        .scrollTargetBehavior(.viewAligned)
    }
}

struct MetricSparkCard: View {
    let item: OverviewMetric
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Drives the goal bar's fill-in on appear (instant under Reduce Motion).
    @State private var barRevealed = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: item.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(item.accent)
                    Text(item.title)
                        .font(Theme.Font.subhead.weight(.medium))
                        .foregroundStyle(Theme.Colors.labelSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(item.value)
                        .font(Theme.Font.statNumber)
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .foregroundStyle(Theme.Colors.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let unit = item.unit {
                        Text(unit)
                            .font(Theme.Font.footnote)
                            .foregroundStyle(Theme.Colors.labelTertiary)
                    }
                }

                Spacer(minLength: Theme.Spacing.sm)

                if !item.sparkline.isEmpty {
                    Sparkline(values: item.sparkline, color: item.accent, width: cardSparkWidth, height: 32)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let progress = item.progress {
                    goalBar(progress)
                }

                if let caption = item.caption {
                    Text(caption)
                        .font(Theme.Font.footnote)
                        .foregroundStyle(Theme.Colors.labelTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
        }
    }

    private func goalBar(_ progress: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colors.fieldBackground).frame(height: 6)
                Capsule().fill(item.accent)
                    .frame(width: geo.size.width * CGFloat(barRevealed || reduceMotion ? progress : 0),
                           height: 6)
            }
        }
        .frame(height: 6)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.5), value: barRevealed)
        .onAppear { barRevealed = true }
        .accessibilityHidden(true)
    }

    private var cardSparkWidth: CGFloat { 168 - Theme.Spacing.lg * 2 }
}
