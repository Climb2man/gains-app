import SwiftUI

@MainActor
struct HealthScreen: View {
    @Environment(AppModel.self) private var appModel
    @State private var whoopModel: WhoopLinkModel?

    /// Navigation routes. A small Hashable enum keeps `Profile` from needing to be Hashable; the editor
    /// reads the live profile from `appModel`.
    private enum Route: Hashable { case profile }

    /// Programmatic path. `ActionCard` is itself a Button, so a wrapping `NavigationLink` had its tap
    /// swallowed by the card and never navigated; the card's own action appends the route instead.
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    if let profile = appModel.profile {
                        profileCard(profile)
                        unitsSection
                    }

                    connectionsSection
                    // Still here, but it now feeds DayCountdownStrip on Overview and Calories rather
                    // than the lock-screen widget, which was removed with the widget target (App
                    // Groups are unavailable on a free Apple ID).
                    DayCountdownSettingsSection()
                    MCPServerSection()
                    dataSection
                    aboutSection
                    footer
                }
                .padding(Theme.Spacing.lg)
                .padding(.bottom, 80)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Health")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .profile:
                    if let profile = appModel.profile {
                        ProfileEditorView(profile: profile)
                    }
                }
            }
        }
        .onAppear {
            if whoopModel == nil {
                whoopModel = WhoopLinkModel(
                    whoop: appModel.whoop,
                    linked: appModel.whoopLinked,
                    onLinkChange: { Task { await appModel.refreshLinks() } }
                )
            }
            Task {
                await appModel.refreshLinks()
                whoopModel?.syncLinked(appModel.whoopLinked)
            }
        }
    }

    /// Hero profile row: person icon, name, and the "Male · 20 · 5'10" · 206 lb" summary of the user's
    /// stored facts. Pushes the editor.
    private func profileCard(_ profile: Profile) -> some View {
        ActionCard(
            icon: "person.crop.circle",
            title: profile.name ?? "Profile",
            subtitle: profileSummary(profile),
            accent: Theme.Colors.tint,
            action: { path.append(.profile) }
        )
    }

    private var unitsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionCaption(title: "Units")
            SettingsGroup {
                SettingsValueRow(
                    icon: "ruler",
                    accent: Theme.Colors.labelSecondary,
                    title: "Measurement system",
                    value: "Imperial"
                )
            }
            Txt(
                "Gains shows weight in pounds and height in feet/inches.",
                variant: .footnote, color: .labelTertiary
            )
        }
    }

    private var connectionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            SectionCaption(
                title: "Connections",
                caption: "The more you connect, the more Gains knows you. Start with what you have."
            )
            if let whoopModel {
                WhoopLinkSection(model: whoopModel)
            }
            // AppleHealthConnectSection() removed: HealthKit cannot be provisioned on a free Apple
            // ID (Gains never appears under iOS Settings → Health → Data Access & Devices), so the
            // section only ever offered a Connect button that silently did nothing. Weight now
            // comes from WHOOP. The file and service are kept for a future paid-account build.
            OpenRouterKeySection(hasKey: appModel.hasAIKey)
        }
    }

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionCaption(title: "Your data")
            SettingsGroup {
                SettingsNavRow(
                    icon: "square.and.arrow.up",
                    accent: Theme.Colors.tint,
                    title: "Export my data"
                ) {}
                SettingsNavRow(
                    icon: "trash",
                    accent: Theme.Colors.danger,
                    title: "Delete my data",
                    destructive: true
                ) {}
            }
            Txt("These controls aren't wired up yet.", variant: .footnote, color: .labelTertiary)
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionCaption(title: "About")
            InsightCard(
                icon: "lock.shield",
                title: "Private by design",
                message: "Gains keeps your Whoop, nutrition, and body data in one private place on "
                    + "this device. A personal tracker.",
                accent: Theme.Colors.tint
            )
        }
    }

    private var footer: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Txt(
                "A private health tracker. Your data stays on this device.",
                variant: .footnote, color: .labelTertiary, center: true
            )
            Txt("Gains · v0", variant: .footnote, color: .labelTertiary, center: true)
        }
        .padding(.top, Theme.Spacing.md)
    }

    /// One-line "Male · 20 · 5'10" · 206 lb" summary of stored facts. Imperial units,
    /// " · " separators. No interpretation.
    private func profileSummary(_ profile: Profile) -> String {
        let sex = profile.sex.rawValue.capitalized
        let height = Format.feetInches(profile.heightCm)
        let weight = Format.weightLb(profile.weightKg)
        return "\(sex) · \(profile.ageYears) · \(height) · \(weight)"
    }
}

#if DEBUG
#Preview {
    HealthScreen()
        .environment(AppModel.sample)
}
#endif
