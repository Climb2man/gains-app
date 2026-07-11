import SwiftUI

struct StreakAdherenceCard: View {
    /// Current consecutive goal-hitting days (counting back from today).
    let streak: Int
    /// Longest streak reached, shown for context.
    let longestStreak: Int
    /// Ordered Sun→Sat: true = both goals hit that day. (Future/unlogged days are false.)
    let weekHits: [Bool]
    /// Deep-link into the Calories tab.
    var onPress: (() -> Void)?

    private let weekdayLabels = ["S", "M", "T", "W", "T", "F", "S"]
    private var hitCount: Int { weekHits.filter { $0 }.count }

    var body: some View {
        TappableCard(onPress: onPress, accessibilityLabel: "Open calories detail") {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                CardHeader(title: "GOAL STREAK", icon: "flame.fill", showsChevron: onPress != nil)

                HStack {
                    StreakBadge(count: streak)
                    Spacer()
                    Txt(longestStreak > 0 ? "Best \(longestStreak)" : "No streak yet",
                        variant: .footnote, color: .labelTertiary)
                }

                AdherenceDots(days: weekHits, labels: weekdayLabels)

                weekProgress
            }
        }
    }

    private var weekProgress: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Txt("\(hitCount) of 7 days on goal this week", variant: .footnote, color: .labelSecondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Colors.fieldBackground).frame(height: 6)
                    Capsule().fill(Theme.Colors.tint)
                        .frame(width: geo.size.width * CGFloat(hitCount) / 7, height: 6)
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }
    }
}

struct StreakBadge: View {
    let count: Int
    var size: CGFloat = 16

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var active: Bool { count > 0 }
    private var tone: Color { active ? Theme.Colors.tint : Theme.Colors.labelTertiary }
    private var unit: String { count == 1 ? "day" : "days" }

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: active ? "flame.fill" : "flame")
                .font(.system(size: size))
                .foregroundStyle(tone)
            Text("\(count)")
                .font(Theme.Font.subhead.weight(.bold))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())
                .foregroundStyle(tone)
            Text(unit)
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.Colors.labelTertiary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, Theme.Spacing.sm + 2)
        .background(
            Capsule()
                .fill(Theme.Colors.fieldBackground)
                .overlay(Capsule().stroke(active ? Theme.Colors.separator : .clear, lineWidth: 1))
        )
        .accessibilityLabel("\(count) \(unit) streak")
    }
}

struct AdherenceDots: View {
    let days: [Bool]
    var labels: [String] = []
    var size: CGFloat = 28

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        HStack {
            ForEach(Array(days.enumerated()), id: \.offset) { index, hit in
                VStack(spacing: Theme.Spacing.xs) {
                    ZStack {
                        Circle()
                            .fill(hit ? Theme.Colors.tint : Color.clear)
                            .overlay(
                                Circle().stroke(hit ? Color.clear : Theme.Colors.separator, lineWidth: 1.5)
                            )
                            .frame(width: size, height: size)
                        if hit {
                            Image(systemName: "checkmark")
                                .font(.system(size: size * 0.5, weight: .semibold))
                                .foregroundStyle(Theme.Colors.background)
                        }
                    }
                    if index < labels.count {
                        Txt(labels[index], variant: .footnote, color: .labelTertiary)
                    }
                }
                .frame(maxWidth: .infinity)
                .opacity(revealed || reduceMotion ? 1 : 0)
                .scaleEffect(revealed || reduceMotion ? 1 : 0.6)
                .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.7)
                    .delay(Double(index) * 0.05), value: revealed)
                .accessibilityLabel(hit ? "goal hit" : "goal missed")
            }
        }
        .onAppear { revealed = true }
    }
}
