import SwiftUI

struct RootTabView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        if appModel.isOnboarded {
            MainTabs()
        } else {
            OnboardingFlow()
        }
    }
}

/// The 4-tab bar plus raised center FAB. Uses the native `TabView` chrome (on iOS 26 already Liquid
/// Glass with a light tinted selected state, no heavy grey pill) and styles it via
/// `GainsTabBarAppearance`. The raised blue FAB is an overlay straddling the bar's top edge in the
/// center seat. Split out from the gate so the gate stays a one-line decision.
private struct MainTabs: View {
    @State private var tab: AppTab = MainTabs.initialTab
    @State private var showingAdd = false
    /// Set by a pushed view (via `HideTabFABKey`) that wants the raised "+" hidden, e.g. the profile
    /// editor, where the FAB is a global overlay that otherwise floats over the Save button. Resets to
    /// false automatically when that view pops (its preference disappears).
    @State private var hideFAB = false
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// DEBUG-only: lets a screenshot harness deep-link the shell to a given tab via a launch argument
    /// (`-initialTab overview|calories|whoop|health`). Release always opens on Overview. There is no
    /// launch-arg path in a shipped build.
    private static var initialTab: AppTab {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "initialTab"),
           let parsed = AppTab(rawValue: raw) {
            return parsed
        }
        #endif
        return .overview
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $tab) {
                ForEach(AppTab.allCases) { appTab in
                    Tab(appTab.title, systemImage: appTab.selectedSystemImage, value: appTab) {
                        screen(appTab)
                    }
                }
            }
            .tint(Theme.Colors.tint)

            if !hideFAB {
                addButton
            }
        }
        .onPreferenceChange(HideTabFABKey.self) { hideFAB = $0 }
        .onAppear(perform: GainsTabBarAppearance.apply)
        .sheet(isPresented: $showingAdd) { QuickLogSheet() }
        #if DEBUG
        .onAppear {
            tab = MainTabs.initialTab
            if UserDefaults.standard.bool(forKey: "showAddFood") { showingAdd = true }
        }
        #endif
    }

    /// The screen for a tab. Each owns its own `NavigationStack`.
    @ViewBuilder
    private func screen(_ appTab: AppTab) -> some View {
        switch appTab {
        case .overview: OverviewScreen(onOpenSettings: { tab = .health })
        case .calories: CaloriesScreen()
        case .whoop: WhoopScreen()
        case .health: HealthScreen()
        }
    }

    /// The elevated center "+": a blue circle straddling the tab bar's top edge, ringed in the
    /// surface color so it reads as floating. Presents `QuickLogSheet` (its AddFoodView composer
    /// auto-focuses on appear). A tinted shadow plus a Reduce-Motion-safe bounce and haptic give depth
    /// and tap feedback.
    private var addButton: some View {
        Button(action: handleAdd) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.Colors.onTint)
                .frame(width: Self.fabSize, height: Self.fabSize)
                .background(Theme.Colors.tint, in: .circle)
                .overlay { Circle().stroke(Theme.Colors.surface, lineWidth: 3) }
                .cardShadow(Theme.Shadow.tinted(Theme.Colors.tint))
                .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : addBounce)
        }
        .accessibilityLabel(tab == .calories ? "Add food" : "Quick add food")
        .sensoryFeedback(.impact(weight: .light), trigger: addBounce)
        .padding(.bottom, Self.fabLift)
    }

    @State private var addBounce = false

    /// The "+" opens the food-add sheet (food logging only; water is logged as a food line).
    private func handleAdd() {
        addBounce.toggle()
        showingAdd = true
    }

    /// FAB geometry.
    private static let fabSize: CGFloat = 56
    /// Half the FAB height plus the floating tab bar's resting height; straddles the bar's top edge.
    private static let fabLift: CGFloat = fabSize / 2 + 6
}

/// Lets a pushed view hide the tab shell's raised "+" FAB (a global overlay it can't otherwise reach).
/// A pushed screen sets `.preference(key: HideTabFABKey.self, value: true)`; `MainTabs` reads it and
/// drops the FAB while that view is on screen, restoring it (default false) once the view pops.
struct HideTabFABKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

#if DEBUG
#Preview("Onboarded (tabs)") {
    RootTabView()
        .environment(AppModel.sample)
}
#endif
