import SwiftUI

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    let store: NutritionStore

    var body: some View {
        let last7 = store.dailyHistory(7)
        let rate7 = store.hitRate(7)

        let logged7 = last7.filter { $0.loggedAnything }
        let avgCalories = logged7.isEmpty ? 0
            : logged7.reduce(0) { $0 + $1.totals.calories } / Double(logged7.count)

        let calorieValues = last7.map { $0.totals.calories }
        let barLabels = last7.map { CaloriesSupport.weekdayInitial($0.date) }
        let latest = calorieValues.last ?? 0

        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Txt("Nutrition history", variant: .largeTitle)

                    summaryCard(values: calorieValues, avgCalories: avgCalories,
                                latest: latest, rate7: rate7)
                    trendCard(last7: last7, values: calorieValues, labels: barLabels)

                    Txt("Your own logged totals vs. goals you set.",
                        variant: .footnote, color: .labelTertiary, center: true)
                }
                .padding(Theme.Spacing.xl)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Calories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "chevron.backward")
                                .font(.system(size: 15, weight: .semibold))
                            Txt("Calories", variant: .body, color: .tint)
                        }
                    }
                }
            }
        }
    }

    private func summaryCard(values: [Double], avgCalories: Double,
                             latest: Double, rate7: HitRate) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Txt("CALORIES · VS YOUR 7-DAY AVERAGE", variant: .sectionHeader, color: .labelSecondary)
                BenchmarkRangeChart(
                    values: values,
                    average: avgCalories > 0 ? avgCalories : nil,
                    averageLabel: avgCalories > 0 ? "Avg \(Format.int(avgCalories))" : nil,
                    color: Theme.Chart.calories,
                    width: WhoopChart.cardWidth, height: 170
                )
                .frame(maxWidth: .infinity, alignment: .center)

                MetricStatStrip(items: [
                    .init(label: "Avg", value: Format.int(avgCalories), unit: "kcal"),
                    .init(label: "Latest", value: Format.int(latest), unit: "kcal"),
                    .init(label: "Hit rate", value: "\(Int((rate7.rate * 100).rounded()))", unit: "%"),
                    .init(label: "Streak", value: "\(store.currentStreak)", unit: "d"),
                ])
            }
        }
    }

    private func trendCard(last7: [DayHistory], values: [Double], labels: [String]) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Txt("DAILY CALORIES VS GOAL", variant: .sectionHeader, color: .labelSecondary)
                GoalBarChart(
                    values: values,
                    goal: store.goals.calorieGoal,
                    color: Theme.Chart.calories,
                    width: WhoopChart.cardWidth, height: 150
                )
                .frame(maxWidth: .infinity, alignment: .center)

                Txt("LAST 7 DAYS", variant: .sectionHeader, color: .labelSecondary)
                AdherenceTones(days: last7.map { $0.hit }, labels: labels)
            }
        }
    }
}

/// The week's goal-adherence as small dots (`StatusTone` palette): a hit reads the good tone, a miss
/// the neutral tone. Describes logged days vs the goal set, never the person. Built inline rather than
/// the shared `AdherenceDots` to keep it scoped to Calories.
private struct AdherenceTones: View {
    let days: [Bool]
    var labels: [String] = []
    var size: CGFloat = 26

    var body: some View {
        HStack {
            ForEach(Array(days.enumerated()), id: \.offset) { index, hit in
                VStack(spacing: Theme.Spacing.xs) {
                    ZStack {
                        let tone: StatusTone = hit ? .good : .neutral
                        Circle()
                            .fill(hit ? tone.color.opacity(0.16) : Theme.Colors.fieldBackground)
                            .frame(width: size, height: size)
                        Image(systemName: hit ? "checkmark" : "minus")
                            .font(.system(size: size * 0.42, weight: .bold))
                            .foregroundStyle(hit ? tone.color : Theme.Colors.labelTertiary)
                    }
                    if index < labels.count {
                        Txt(labels[index], variant: .footnote, color: .labelTertiary)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel(hit ? "goal hit" : "goal missed")
            }
        }
    }
}

#if DEBUG
#Preview("History") {
    HistoryView(store: AppModel.sample.nutritionStore)
        .environment(AppModel.sample)
}
#endif
