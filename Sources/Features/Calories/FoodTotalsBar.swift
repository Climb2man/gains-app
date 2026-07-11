import SwiftUI

struct FoodTotalsBar: View {
    let totals: FoodDayTotals
    let goals: Goals

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            calorieHeadline
            if totals.waterMilliliters > 0 {
                waterRow
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface)
        .overlay(alignment: .top) { HairlineDivider() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var over: Bool {
        goals.calorieGoal > 0 && totals.calories > goals.calorieGoal
    }

    private var calorieHeadline: some View {
        HStack(alignment: .firstTextBaseline) {
            Txt("TODAY'S TOTAL", variant: .sectionHeader, color: .labelSecondary)
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Format.int(totals.calories))")
                    .font(Theme.Font.statNumber)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(over ? Theme.Colors.warning : Theme.Colors.label)
                Text("/ \(Format.int(goals.calorieGoal)) kcal")
                    .font(Theme.Font.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.labelTertiary)
            }
        }
    }

    private var waterRow: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "drop.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Chart.recovery)
            Txt(FoodLogFormat.water(totals.waterMilliliters), variant: .footnote, color: .labelSecondary)
            Spacer(minLength: 0)
        }
    }

    private var accessibilitySummary: String {
        "Today's total \(Format.int(totals.calories)) of \(Format.int(goals.calorieGoal)) kilocalories"
    }
}

#if DEBUG
#Preview("Totals bar") {
    VStack {
        Spacer()
        FoodTotalsBar(
            totals: FoodDayTotals(calories: 1840, proteinG: 132, carbsG: 180, fatG: 61,
                                  waterMilliliters: 950),
            goals: .default
        )
    }
    .background(Theme.Colors.background)
}
#endif
