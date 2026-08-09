import SwiftUI

@MainActor
struct ProfileEditorView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    private let profile: Profile

    @State private var name: String
    @State private var saved = false

    init(profile: Profile) {
        self.profile = profile
        _name = State(initialValue: profile.name ?? "")
    }

    /// Trimmed name to save, capped at 60 chars; empty becomes nil.
    private var candidateName: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(60))
    }

    /// The live profile. Everything except the name is WHOOP-owned and read-only here, so it must
    /// come from the current profile rather than a value snapshotted when the editor opened —
    /// otherwise a WHOOP sync landing while this screen is open would be silently reverted the
    /// moment the user saved their name.
    private var live: Profile? { appModel.profile ?? profile }

    private var liveWeightKg: Double { live?.weightKg ?? profile.weightKg }

    private var profileSexLabel: String {
        switch live?.sex {
        case .male: return "Male"
        case .female: return "Female"
        case .other: return "Other"
        case nil: return "—"
        }
    }

    private var profileHeightLabel: String {
        guard let cm = live?.heightCm, cm > 0 else { return "—" }
        let ftIn = Units.cmToFtIn(cm)
        return "\(ftIn.feet)' \(ftIn.inches)\""
    }

    /// Candidate Profile: the live profile with only the name replaced, since the name is now the
    /// one editable field on this screen.
    private var candidate: Profile? {
        guard var next = live else { return nil }
        next.name = candidateName
        return next
    }

    /// Only the name can differ. The WHOOP-owned fields are excluded so a background sync cannot
    /// light up the Save button on a screen the user has not touched.
    private var changed: Bool {
        candidateName != profile.name
    }

    private var bmrText: String {
        Format.int(EnergyMath.computeBmr(candidate ?? profile))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Card(metricAccent: Theme.Chart.calories) {
                    Txt(
                        "Used for your reference ranges and your resting-energy estimate. Fix anything onboarding got wrong.",
                        variant: .footnote, color: .labelSecondary
                    )

                    FormField(
                        label: "Name (for your dashboard greeting)",
                        text: $name,
                        placeholder: "optional",
                        autocap: .words
                    )

                    // Sex, age and height are read-only for the same reason as weight:
                    // AppModel.syncProfileFromWhoop() adopts all three from WHOOP on every launch,
                    // so an editable field here would accept a change and silently lose it at the
                    // next sync. Sex is included even though only age and height were asked for —
                    // it is overwritten by exactly the same code path, so leaving it editable would
                    // have preserved the bug rather than fixed it.
                    readOnlyRow("Sex", value: profileSexLabel)
                    readOnlyRow("Age", value: appModel.profile.map { "\($0.ageYears)" } ?? "—")
                    readOnlyRow("Height", value: profileHeightLabel)

                    // Weight is read-only: WHOOP owns it. A smart scale pushes to WHOOP and
                    // AppModel.syncWeightFromWhoop() adopts the value, so an editable field here
                    // would just be overwritten on the next sync and mislead about the source.
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        HStack {
                            Txt("Weight", variant: .body, color: .labelSecondary)
                            Spacer(minLength: 0)
                            Txt(liveWeightKg > 0 ? "\(Units.formatLb(liveWeightKg)) lb" : "—",
                                variant: .body, color: .label)
                        }
                        .padding(.vertical, Theme.Spacing.xs)

                        Txt(
                            appModel.whoopLinked
                                ? "Weight comes from WHOOP. Change it in the WHOOP app (or step on "
                                    + "your scale) and it updates here on the next sync."
                                : "Weight comes from WHOOP. Connect WHOOP to start tracking it.",
                            variant: .footnote, color: .labelTertiary
                        )
                    }

                    EstimateStrip(
                        label: "Resting energy",
                        value: bmrText,
                        unit: "cal/day",
                        infoBody: "An estimate from your profile (sex, age, height, weight), not a "
                            + "medical measurement. It updates your Energy Balance as you edit these basics."
                    )

                    AppButton(title: "Save", kind: .primary) { save() }
                        .disabled(!changed)

                    if saved {
                        Txt(
                            "Saved. Your profile and Energy Balance are up to date.",
                            variant: .footnote, color: .labelSecondary, center: true
                        )
                    }
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Colors.background)
        .navigationTitle("Your profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .preference(key: HideTabFABKey.self, value: true)
        .onChange(of: editSignature) { saved = false }
    }

    /// Changes whenever an editable field does, so one `onChange` can clear the "saved"
    /// confirmation. Only the name qualifies now; a background WHOOP sync must not clear it.
    private var editSignature: String { name }

    /// A WHOOP-sourced field: label on the left, value on the right, not editable.
    private func readOnlyRow(_ label: String, value: String) -> some View {
        HStack {
            Txt(label, variant: .body, color: .labelSecondary)
            Spacer(minLength: 0)
            Txt(value, variant: .body, color: .label)
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement()
        .accessibilityLabel("\(label): \(value)")
    }

    private func save() {
        guard let candidate, changed else { return }
        // Name is the only editable field left and it does not feed the BMR, so there is nothing to
        // recompute. The WHOOP-owned values that DO affect it are refreshed on their own schedule.
        appModel.updateProfile(candidate)
        saved = true
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ProfileEditorView(profile: SampleData.profile)
            .environment(AppModel.sample)
    }
}
#endif
