import SwiftUI

struct CaloriesScreen: View {
    @Environment(AppModel.self) private var appModel

    @State private var showingInsights = false
    @State private var showingGoals = false
    @State private var showingHistory = false
    @State private var showingSavedMeals = false
    /// The scrubbable calorie detail sheet, opened by tapping the header's calorie ring.
    @State private var showingCalorieDetail = false

    private var store: NutritionStore { appModel.nutritionStore }

    var body: some View {
        NavigationStack {
            FoodLogView(
                appModel: appModel,
                onOpenInsights: { showingInsights = true },
                onOpenDetail: { showingCalorieDetail = true }
            )
            .navigationTitle("Calories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingHistory = true } label: {
                        StreakBadge(count: store.currentStreak)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open nutrition history")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showingSavedMeals = true } label: {
                            Label("Saved meals", systemImage: "bookmark")
                        }
                        Button { showingGoals = true } label: {
                            Label("Edit goals", systemImage: "target")
                        }
                        Button { showingHistory = true } label: {
                            Label("Nutrition history", systemImage: "calendar")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(Theme.Colors.tint)
                    }
                    .accessibilityLabel("More: saved meals, edit goals, nutrition history")
                }
            }
        }
        .sheet(isPresented: $showingInsights) {
            CalorieInsightsSheet(
                store: store,
                onEditGoals: { showingInsights = false; showingGoals = true },
                onHistory: { showingInsights = false; showingHistory = true }
            )
        }
        .sheet(isPresented: $showingGoals) {
            GoalsView(goals: store.goals) { store.setGoals($0) }
        }
        .sheet(isPresented: $showingHistory) {
            HistoryView(store: store)
        }
        .sheet(isPresented: $showingSavedMeals) {
            NavigationStack { SavedMealsScreen() }
        }
        .sheet(isPresented: $showingCalorieDetail) {
            calorieDetailSheet
        }
    }

    private var calorieDetailSheet: some View {
        let detail = CalorieDetailData(store: store)
        return MetricDetailSheet(
            title: "Calories",
            value: Format.int(detail.latest),
            unit: "kcal",
            date: detail.latestDateLabel,
            rangeLabel: "vs your 7-day average",
            series: detail.series,
            labels: detail.labels,
            color: Theme.Chart.calories,
            pills: ["Calories", "Protein", "Carbs", "Fat"],
            statStripItems: detail.statStripItems,
            goalLine: store.goals.calorieGoal,
            onClose: { showingCalorieDetail = false }
        )
        .presentationDetents([.large])
        .presentationCornerRadius(28)
    }
}

/// The user's last 7 days of logged calories vs goal, for the detail sheet.
private struct CalorieDetailData {
    let series: [Double]
    let labels: [String]
    let latest: Double
    let latestDateLabel: String
    let statStripItems: [MetricStatStrip.Item]

    @MainActor
    init(store: NutritionStore) {
        let days = store.dailyHistory(7)
        let values = days.map { $0.totals.calories }
        series = values
        labels = days.map { CaloriesSupport.weekdayInitial($0.date) }
        latest = values.last ?? 0
        latestDateLabel = CaloriesSupport.dayTitle(days.last?.date ?? CaloriesSupport.dayKey(.now))

        let logged = values.filter { $0 > 0 }
        let avg = logged.isEmpty ? 0 : logged.reduce(0, +) / Double(logged.count)
        statStripItems = [
            .init(label: "Avg", value: Format.int(avg), unit: "kcal"),
            .init(label: "Min", value: Format.int(logged.min() ?? 0), unit: "kcal"),
            .init(label: "Max", value: Format.int(logged.max() ?? 0), unit: "kcal"),
            .init(label: "Latest", value: Format.int(values.last ?? 0), unit: "kcal"),
        ]
    }
}

#if DEBUG
#Preview("Calories") {
    CaloriesScreen()
        .environment(AppModel.sample)
}
#endif
