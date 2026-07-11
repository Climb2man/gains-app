import SwiftUI

struct CalorieInsightsSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let store: NutritionStore
    let onEditGoals: () -> Void
    let onHistory: () -> Void

    private var totals: FoodDayTotals {
        appModel.foodLog.totals(on: FoodLogStore.dayKey(.now))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    InsightRingsCard(totals: totals, goals: store.goals)
                    InsightMacroDonut(totals: totals)
                    let qualities = CaloriesSupport.foodQualities(totals)
                    if !qualities.isEmpty {
                        FoodQualityCard(items: qualities)
                    }
                    ActionCard(icon: "target", title: "Edit goals",
                                    accent: Theme.Chart.calories, action: onEditGoals)
                    ActionCard(icon: "calendar", title: "Nutrition history",
                                    accent: Theme.Colors.tint, action: onHistory)
                    Txt("Macro numbers are estimates.",
                        variant: .footnote, color: .labelTertiary, center: true)
                }
                .padding(Theme.Spacing.xl)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Today's macros")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
    }
}

private struct InsightRingsCard: View {
    let totals: FoodDayTotals
    let goals: Goals

    var body: some View {
        let calorieRemaining = max(0, goals.calorieGoal - totals.calories)
        let calorieProgress = goals.calorieGoal > 0 ? totals.calories / goals.calorieGoal : 0
        let over = totals.calories > goals.calorieGoal && goals.calorieGoal > 0
        let proteinProgress = goals.proteinGoal > 0 ? totals.proteinG / goals.proteinGoal : 0
        let proteinMet = goals.proteinGoal > 0 && totals.proteinG >= goals.proteinGoal

        return Card {
            HStack(alignment: .center, spacing: Theme.Spacing.lg) {
                Spacer(minLength: 0)
                RingChart(
                    progress: calorieProgress,
                    size: 156,
                    strokeWidth: 16,
                    color: over ? Theme.Colors.warning : Theme.Chart.calories
                ) {
                    VStack(spacing: 2) {
                        Txt(over ? "OVER BY" : "REMAINING", variant: .footnote, color: .labelSecondary)
                        Text(Format.int(over ? totals.calories - goals.calorieGoal : calorieRemaining))
                            .font(Theme.Font.metricNumber)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(Theme.Colors.label)
                        Txt("kcal vs your goal", variant: .footnote, color: .labelTertiary)
                        Txt("\(Format.int(totals.calories)) / \(Format.int(goals.calorieGoal))",
                            variant: .footnote, color: .labelTertiary)
                    }
                }
                Spacer(minLength: 0)
                VStack(spacing: Theme.Spacing.sm) {
                    RingChart(progress: proteinProgress, size: 108, strokeWidth: 12, color: Theme.Chart.protein) {
                        VStack(spacing: 2) {
                            Txt(Format.int(totals.proteinG), variant: .title2)
                            Txt("/ \(Format.int(goals.proteinGoal)) g", variant: .footnote, color: .labelTertiary)
                        }
                    }
                    Txt(proteinMet ? "Protein goal met" : "Protein",
                        variant: .footnote, color: proteinMet ? .success : .labelSecondary)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct InsightMacroDonut: View {
    let totals: FoodDayTotals

    private struct Macro: Identifiable {
        let key: String
        let label: String
        let grams: Double
        let cals: Double
        let color: Color
        var id: String { key }
    }

    var body: some View {
        let macros = [
            Macro(key: "protein", label: "Protein", grams: totals.proteinG,
                  cals: totals.proteinG * CaloriesSupport.kcalPerProteinG, color: Theme.Chart.protein),
            Macro(key: "carbs", label: "Carbs", grams: totals.carbsG,
                  cals: totals.carbsG * CaloriesSupport.kcalPerCarbG, color: Theme.Chart.carbs),
            Macro(key: "fat", label: "Fat", grams: totals.fatG,
                  cals: totals.fatG * CaloriesSupport.kcalPerFatG, color: Theme.Chart.fat),
        ]
        let totalCals = macros.reduce(0) { $0 + $1.cals }
        let hasData = totalCals > 0

        return Card {
            Txt("MACROS", variant: .sectionHeader, color: .labelSecondary)
            HStack(alignment: .center, spacing: Theme.Spacing.xl) {
                MacroDonut(
                    segments: macros.map { (value: $0.cals, color: $0.color, label: $0.label) },
                    size: 132,
                    strokeWidth: 16,
                    centerLabel: hasData ? Format.int(totalCals) : "–",
                    centerSubLabel: hasData ? "kcal" : "no food yet"
                )
                VStack(spacing: Theme.Spacing.md) {
                    ForEach(macros) { macro in
                        let pct = totalCals > 0 ? Int((macro.cals / totalCals * 100).rounded()) : 0
                        HStack(spacing: Theme.Spacing.sm) {
                            Circle().fill(macro.color).frame(width: 10, height: 10)
                            Txt(macro.label, variant: .subhead)
                            Spacer(minLength: 0)
                            Txt("\(Format.int(macro.grams)) g · \(pct)%",
                                variant: .subhead, color: .labelSecondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            if !hasData {
                Txt("Log a meal to see your macro split.", variant: .footnote, color: .labelTertiary)
            }
        }
    }
}

#if DEBUG
#Preview("Insights") {
    CalorieInsightsSheet(
        store: AppModel.sample.nutritionStore,
        onEditGoals: {}, onHistory: {}
    )
    .environment(AppModel.sample)
}
#endif
