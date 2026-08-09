import SwiftUI

/// Calories left today, as the first card on Overview.
///
/// The Calories tab already has a remaining ring (`CalorieOverviewHeader`), but it is built on
/// `FoodDayTotals` where Overview works in `DailyTotals`, and it pairs the ring with a protein ring
/// and a macros card. Rather than convert types and inherit that layout, this is the same idea at
/// Overview's scale: one ring, one number, no companions.
///
/// The reading is the interface — the remaining number is set at hero size so it is legible before
/// any label is read, and the ring turns amber the moment the goal is passed.
struct CaloriesRemainingCard: View {
    let totals: DailyTotals
    let goals: Goals
    /// Header label; carries the day when Overview is scoped to a past date.
    var title: String = "CALORIES LEFT"
    /// Deep-link into the Calories tab.
    var onPress: (() -> Void)?

    private var eaten: Double { totals.calories }
    private var goal: Double { goals.calorieGoal }
    private var hasGoal: Bool { goal > 0 }
    private var over: Bool { hasGoal && eaten > goal }
    private var remaining: Double { max(0, goal - eaten) }
    /// Ring fill. Clamped at 1 so going over does not wind the arc round a second time.
    private var progress: Double { hasGoal ? min(1, eaten / goal) : 0 }
    private var ringColor: Color { over ? Theme.Colors.warning : Theme.Chart.calories }

    var body: some View {
        Card(metricAccent: ringColor) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                CardHeader(title: title, icon: "flame.fill")

                if hasGoal {
                    HStack(spacing: Theme.Spacing.xl) {
                        ring
                        readout
                        Spacer(minLength: 0)
                    }
                } else {
                    Txt("Set a goal to see what's left.", variant: .footnote, color: .labelTertiary)
                }
            }
        }
        .onTapGesture { onPress?() }
    }

    private var ring: some View {
        RingChart(progress: progress, size: 132, strokeWidth: 13, color: ringColor, glow: false) {
            VStack(spacing: 0) {
                Text(Format.int(over ? eaten - goal : remaining))
                    .font(Theme.Font.number(size: 38, weight: .bold))
                    .foregroundStyle(Theme.Colors.label)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(over ? "OVER" : "LEFT")
                    .font(Theme.Font.footnote.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.Colors.labelSecondary)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(
            over
                ? "\(Format.int(eaten - goal)) kilocalories over your goal of \(Format.int(goal))"
                : "\(Format.int(remaining)) kilocalories left of \(Format.int(goal))"
        )
    }

    private var readout: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            statRow("Eaten", value: Format.int(eaten))
            statRow("Goal", value: Format.int(goal))
            if over {
                Txt("Over by \(Format.int(eaten - goal))", variant: .footnote, color: .warning)
            }
        }
    }

    private func statRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Txt(label, variant: .footnote, color: .labelTertiary)
            Text(value)
                .font(Theme.Font.statNumber)
                .foregroundStyle(Theme.Colors.label)
                .monospacedDigit()
        }
    }
}
