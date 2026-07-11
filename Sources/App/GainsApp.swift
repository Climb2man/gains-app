import SwiftUI

@main
struct GainsApp: App {
    /// The one app-state container, owned for the whole process lifetime.
    ///
    /// Every build defaults to the real container, so the simulator shows live data exactly like the
    /// phone. The populated demo container is opt-in via `-sampleData YES` (passed by the screenshot
    /// harness in `scripts/build.sh`); release compiles the real container only.
    ///
    /// Foreground hook: re-resolve launch state and roll the day scope when the app re-activates (the
    /// overnight-suspend case, see `rootScene`).
    @Environment(\.scenePhase) private var scenePhase

    @State private var appModel: AppModel = {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "sampleData") {
            return .sample
        }
        if UserDefaults.standard.bool(forKey: "forceOnboarding") {
            return AppModel()
        }
        if UserDefaults.standard.bool(forKey: "emptyState") {
            return .emptyOnboarded
        }
        #endif
        return AppModel()
    }()

    var body: some Scene {
        WindowGroup {
            content
                .preferredColorScheme(.light)
        }
    }

    /// The window's root view, chosen by the DEBUG launch-arg hooks (else the real app shell).
    @ViewBuilder
    private var content: some View {
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "showWidgetPreview") {
                WidgetPreviewCanvas()
            } else if UserDefaults.standard.bool(forKey: "showWorkoutLog") {
                NavigationStack { WorkoutLogScreen(store: appModel.workoutLog) }
                    .environment(appModel)
            } else if UserDefaults.standard.bool(forKey: "showJournal") {
                NavigationStack { JournalScreen(store: appModel.journal) }
                    .environment(appModel)
            } else if UserDefaults.standard.bool(forKey: "showCalorieMockups") {
                CalorieMockupsCanvas()
            } else if UserDefaults.standard.bool(forKey: "showGoalCalculator") {
                GoalCalculatorSheet(profile: appModel.profile, onApply: { _ in })
                    .background(Theme.Colors.background)
            } else if UserDefaults.standard.bool(forKey: "showGoals") {
                GoalsView(goals: appModel.nutritionStore.goals) { _ in }
                    .environment(appModel)
                    .background(Theme.Colors.background)
            } else {
                rootScene
            }
            #else
            rootScene
            #endif
    }

    /// The real app shell: the tabs (or onboarding gate) with the model injected + launch state loaded.
    private var rootScene: some View {
        RootTabView()
            .environment(appModel)
            .task { await appModel.load() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                if !appModel.usesSampleData, !Calendar.current.isDateInToday(appModel.selectedDate) {
                    appModel.selectedDate = Date()
                }
                Task { await appModel.load() }
                appModel.nutritionStore.syncWidgetSnapshot()
                if let profile = appModel.profile {
                    appModel.nutritionStore.autoAdjustGoals(profile: profile)
                }
            }
    }
}

#if DEBUG
/// DEBUG-only canvas that renders the widget variants (lock-screen day-countdown and home-screen
/// calories) at their real sizes, so `-showWidgetPreview YES` lets the screenshot loop verify the
/// widgets via the running app (WidgetKit extensions can't be screenshotted standalone in the
/// simulator-only loop). Uses a fixed sample snapshot: illustrative numbers, never the user's data.
private struct WidgetPreviewCanvas: View {
    /// Illustrative under-goal snapshot for the home-screen variants. Matches the sample dashboard's
    /// numbers (1,580 of 2,800 → 1,220 left) so the widget and the app screenshots stay consistent.
    private let sample = WidgetSnapshot(date: "2026-06-07", caloriesConsumed: 1580, calorieGoal: 2800)
    /// A sample target ~24 days out for the day-countdown preview.
    private var countdownTarget: Date {
        Calendar.current.date(byAdding: .day, value: 24, to: Date()) ?? Date()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                sectionTitle("Lock Screen", "Day countdown")

                DayCountdownView(daysLeft: 24, label: "Trip", targetDate: countdownTarget,
                                 family: .accessoryRectangular)
                    .foregroundStyle(.white)
                    .frame(width: 170, height: 72, alignment: .leading)
                    .padding(.horizontal, Theme.Spacing.md)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.black))
                HStack(spacing: Theme.Spacing.xl) {
                    DayCountdownView(daysLeft: 24, targetDate: countdownTarget, family: .accessoryCircular)
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(Circle().fill(.black))
                    DayCountdownView(daysLeft: 24, label: "Trip", targetDate: countdownTarget,
                                     family: .accessoryInline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Capsule().fill(.black))
                }

                sectionTitle("Home Screen", "Calories")
                    .padding(.top, Theme.Spacing.lg)

                widgetTile(size: CGSize(width: 158, height: 158)) {
                    CaloriesWidgetView(snapshot: sample, family: .systemSmall)
                }
                widgetTile(size: CGSize(width: 338, height: 158)) {
                    CaloriesWidgetView(snapshot: sample, family: .systemMedium)
                }
            }
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.Colors.background)
    }

    /// A two-line section heading: a small kicker ("Lock Screen") over the widget name ("Day countdown").
    private func sectionTitle(_ kicker: String, _ name: String) -> some View {
        VStack(spacing: 2) {
            Text(kicker.uppercased())
                .font(Theme.Font.sectionHeader)
                .tracking(0.6)
                .foregroundStyle(Theme.Colors.labelTertiary)
            Text(name)
                .font(Theme.Font.title2)
                .foregroundStyle(Theme.Colors.label)
        }
    }

    /// A card framing one Home-Screen widget variant at its real point size, on a white surface with the
    /// app's card shadow, so the screenshot reads like the widget on a wallpaper.
    private func widgetTile<Content: View>(
        size: CGSize,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(width: size.width, height: size.height)
            .background(Theme.Colors.surface)
            .clipShape(.rect(cornerRadius: Theme.Radius.card, style: .continuous))
            .cardShadow()
    }
}
#endif
