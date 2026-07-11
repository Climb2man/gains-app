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
    private var proteinProgress: Double {
        goals.proteinGoal > 0 ? min(1, totals.proteinG / goals.proteinGoal) : 0
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            remainingCard
            macrosCard
        }
    }

    private var remainingCard: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.lg) {
            Button(action: onOpenDetail) { remainingRing }
                .buttonStyle(.plain)
            proteinRing
        }
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

    private var proteinRing: some View {
        VStack(spacing: Theme.Spacing.sm) {
            RingChart(progress: proteinProgress, size: 112, strokeWidth: 12,
                      color: Theme.Chart.protein, glow: false) {
                VStack(spacing: 0) {
                    Text(Format.int(totals.proteinG))
                        .font(Theme.Font.number(size: 24, weight: .bold))
                        .foregroundStyle(Theme.Colors.label)
                        .monospacedDigit()
                    Text("/ \(Format.int(goals.proteinGoal)) g")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Colors.labelTertiary)
                }
            }
            Text("Protein")
                .font(Theme.Font.footnote.weight(.medium))
                .foregroundStyle(Theme.Colors.labelSecondary)
        }
        .accessibilityElement()
        .accessibilityLabel("Protein \(Format.int(totals.proteinG)) of \(Format.int(goals.proteinGoal)) grams")
    }

    private let kcalPerProteinG = 4.0, kcalPerCarbG = 4.0, kcalPerFatG = 9.0
    private var macroCals: Double {
        totals.proteinG * kcalPerProteinG + totals.carbsG * kcalPerCarbG + totals.fatG * kcalPerFatG
    }
    private var hasMacros: Bool { macroCals > 0 }

    private var macrosCard: some View {
        Card(metricAccent: Theme.Chart.protein) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("MACROS")
                    .font(Theme.Font.footnote.weight(.semibold)).tracking(0.5)
                    .foregroundStyle(Theme.Colors.labelTertiary)
                HStack(spacing: Theme.Spacing.xl) {
                    ZStack {
                        DonutChart(
                            segments: [
                                DonutSegment(value: totals.proteinG * kcalPerProteinG, color: Theme.Chart.protein, label: "Protein"),
                                DonutSegment(value: totals.carbsG * kcalPerCarbG, color: Theme.Chart.carbs, label: "Carbs"),
                                DonutSegment(value: totals.fatG * kcalPerFatG, color: Theme.Chart.fat, label: "Fat"),
                            ],
                            size: 128, strokeWidth: 16
                        )
                        VStack(spacing: 2) {
                            Text(hasMacros ? Format.int(macroCals) : "–")
                                .font(Theme.Font.statNumber).monospacedDigit()
                                .foregroundStyle(Theme.Colors.label)
                            Text(hasMacros ? "kcal" : "no food yet")
                                .font(Theme.Font.footnote)
                                .foregroundStyle(Theme.Colors.labelSecondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        macroLegendRow("Protein", totals.proteinG, kcalPerProteinG, Theme.Chart.protein)
                        macroLegendRow("Carbs", totals.carbsG, kcalPerCarbG, Theme.Chart.carbs)
                        macroLegendRow("Fat", totals.fatG, kcalPerFatG, Theme.Chart.fat)
                    }
                }
            }
        }
    }

    private func macroLegendRow(_ label: String, _ grams: Double, _ kcalPerG: Double, _ color: Color) -> some View {
        let pct = macroCals > 0 ? Int((grams * kcalPerG / macroCals * 100).rounded()) : 0
        return HStack(spacing: Theme.Spacing.sm) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label).font(Theme.Font.subhead).foregroundStyle(Theme.Colors.label)
            Spacer(minLength: 0)
            Text("\(Format.int(grams)) g · \(pct)%")
                .font(Theme.Font.subhead)
                .foregroundStyle(Theme.Colors.labelSecondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(Format.int(grams)) grams, \(pct) percent")
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
