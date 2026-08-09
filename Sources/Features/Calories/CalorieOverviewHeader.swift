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
                VStack(spacing: Theme.Spacing.lg) {
                    macroRing("Protein", totals.proteinG, goals.proteinGoal, Theme.Chart.protein)
                    HairlineDivider()
                    macroRing("Carbs", totals.carbsG, goals.carbGoal, Theme.Chart.carbs)
                    HairlineDivider()
                    macroRing("Fat", totals.fatG, goals.fatGoal, Theme.Chart.fat)
                }
            }
        }
    }

    /// One macro row: ring on the left, name and numbers beside it.
    ///
    /// Stacked vertically rather than three abreast. Side by side, each ring got roughly a third of
    /// the width — tight on a smaller iPhone, and it forced the grams to shrink to fit inside the
    /// ring. Down the page each row gets the full width, so the ring can stay a legible size and the
    /// numbers can sit outside it at full size instead of being squeezed into the middle.
    ///
    /// Fill clamps at 1 so passing the goal does not wind the arc round again; the percentage keeps
    /// counting past 100 so going over is still visible.
    private func macroRing(_ label: String, _ eatenG: Double, _ goalG: Double, _ color: Color)
        -> some View {
        let pct = goalG > 0 ? eatenG / goalG : 0
        let over = goalG > 0 && eatenG > goalG
        return HStack(spacing: Theme.Spacing.lg) {
            RingChart(progress: min(1, pct), size: 74, strokeWidth: 9,
                      color: over ? Theme.Colors.warning : color, glow: false) {
                Text(goalG > 0 ? "\(Int((pct * 100).rounded()))%" : "–")
                    .font(Theme.Font.number(size: 17, weight: .bold))
                    .foregroundStyle(Theme.Colors.label)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.sm) {
                    Circle().fill(over ? Theme.Colors.warning : color).frame(width: 9, height: 9)
                    Text(label)
                        .font(Theme.Font.bodyEmphasized)
                        .foregroundStyle(Theme.Colors.label)
                }
                Text("\(Format.int(eatenG)) / \(Format.int(goalG)) g")
                    .font(Theme.Font.statNumber)
                    .foregroundStyle(Theme.Colors.labelSecondary)
                    .monospacedDigit()
                if goalG > 0 {
                    Text(over
                        ? "\(Format.int(eatenG - goalG)) g over"
                        : "\(Format.int(goalG - eatenG)) g to go")
                        .font(Theme.Font.footnote)
                        .foregroundStyle(over ? Theme.Colors.warning : Theme.Colors.labelTertiary)
                }
            }
            Spacer(minLength: 0)
        }
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
