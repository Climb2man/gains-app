import SwiftUI

struct CalorieOverviewHeader: View {
    let totals: FoodDayTotals
    let goals: Goals
    /// Opens the scrubbable calorie detail; tapped from the remaining ring.
    let onOpenDetail: () -> Void

    private var eaten: Double { totals.calories }
    private var remaining: Double { max(0, goals.calorieGoal - eaten) }
    private var over: Bool { goals.calorieGoal > 0 && eaten > goals.calorieGoal }
    private var calProgress: Double { goals.calorieGoal > 0 ? eaten / goals.calorieGoal : 0 }
    private var ringColor: Color { over ? Theme.Colors.warning : Theme.Chart.calories }

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            remainingCard
            macrosCard
        }
    }

    /// Just the calorie ring, centred. The protein ring that used to sit beside it is gone: the
    /// macros card below now carries a protein ring of its own, and showing the same number twice
    /// on one screen makes the second one look like a different measurement.
    private var remainingCard: some View {
        Button(action: onOpenDetail) { remainingRing }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.sm)
    }

    private var remainingRing: some View {
        RingChart(progress: calProgress, size: 152, strokeWidth: 14, color: ringColor, glow: false) {
            VStack(spacing: 1) {
                Text(over ? "OVER" : "REMAINING")
                    .font(Theme.Font.footnote.weight(.semibold)).tracking(0.5)
                    .foregroundStyle(Theme.Colors.labelSecondary)
                Text(Format.int(over ? eaten - goals.calorieGoal : remaining))
                    .font(Theme.Font.number(size: 32, weight: .bold))
                    .foregroundStyle(Theme.Colors.label)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("kcal vs your goal")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Colors.labelTertiary)
                Text("\(Format.int(eaten)) / \(Format.int(goals.calorieGoal))")
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Colors.labelTertiary)
                    .monospacedDigit()
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(Format.int(remaining)) kilocalories remaining of \(Format.int(goals.calorieGoal))")
        .accessibilityHint("Opens the calorie trend")
    }


    /// Three rings, one per macro, each filled to its share of that macro's GOAL.
    ///
    /// This replaced a donut of the macro split. The donut answered "what proportion of what I ate
    /// was protein" — a question nobody asks mid-afternoon. These answer "how much of today's
    /// protein have I got in", which is the one that decides what to eat next, and it matches the
    /// mental model of closing rings.
    private var macrosCard: some View {
        Card(metricAccent: Theme.Chart.protein) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("MACROS")
                    .font(Theme.Font.footnote.weight(.semibold)).tracking(0.5)
                    .foregroundStyle(Theme.Colors.labelTertiary)
                HStack(spacing: Theme.Spacing.md) {
                    macroRing("Protein", totals.proteinG, goals.proteinGoal, Theme.Chart.protein)
                    macroRing("Carbs", totals.carbsG, goals.carbGoal, Theme.Chart.carbs)
                    macroRing("Fat", totals.fatG, goals.fatGoal, Theme.Chart.fat)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// One macro ring. Fill clamps at 1 so passing the goal does not wind the arc round again; the
    /// percentage underneath keeps counting so going over is still visible.
    private func macroRing(_ label: String, _ eatenG: Double, _ goalG: Double, _ color: Color)
        -> some View {
        let pct = goalG > 0 ? eatenG / goalG : 0
        let over = goalG > 0 && eatenG > goalG
        return VStack(spacing: Theme.Spacing.sm) {
            RingChart(progress: min(1, pct), size: 92, strokeWidth: 10,
                      color: over ? Theme.Colors.warning : color, glow: false) {
                VStack(spacing: 0) {
                    Text(goalG > 0 ? "\(Int((pct * 100).rounded()))%" : "–")
                        .font(Theme.Font.number(size: 19, weight: .bold))
                        .foregroundStyle(Theme.Colors.label)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("\(Format.int(eatenG))/\(Format.int(goalG))")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Colors.labelTertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            Text(label)
                .font(Theme.Font.footnote.weight(.medium))
                .foregroundStyle(Theme.Colors.labelSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel(
            "\(label) \(Format.int(eatenG)) of \(Format.int(goalG)) grams, "
                + "\(Int((pct * 100).rounded())) percent"
        )
    }

}

#if DEBUG
#Preview("Calorie overview") {
    ScrollView {
        CalorieOverviewHeader(
            totals: FoodDayTotals(calories: 1580, proteinG: 120, carbsG: 160, fatG: 49),
            goals: .default,
            onOpenDetail: {}
        )
        .padding(Theme.Spacing.lg)
    }
    .background(Theme.Colors.background)
}
#endif
