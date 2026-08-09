import SwiftUI

@MainActor
struct ProfileEditorView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    private let profile: Profile

    @State private var name: String
    @State private var sex: Sex?
    @State private var age: String
    @State private var feet: String
    @State private var inches: String
    @State private var saved = false

    init(profile: Profile) {
        self.profile = profile
        let ftIn = Units.cmToFtIn(profile.heightCm)
        _name = State(initialValue: profile.name ?? "")
        _sex = State(initialValue: profile.sex)
        _age = State(initialValue: String(profile.ageYears))
        _feet = State(initialValue: String(ftIn.feet))
        _inches = State(initialValue: String(ftIn.inches))
    }

    /// Trimmed name to save, capped at 60 chars; empty becomes nil.
    private var candidateName: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(60))
    }

    /// Weight is WHOOP-owned and read-only in this editor, so it must be read from the LIVE profile
    /// and never from a value snapshotted when the editor opened. Without this, a WHOOP sync landing
    /// while the editor is open would be silently reverted the moment the user saved an unrelated
    /// field (name, age, height).
    private var liveWeightKg: Double { appModel.profile?.weightKg ?? profile.weightKg }

    private var basicValid: Bool {
        sex != nil && (Int(age) ?? 0) > 0 && (Int(feet) ?? 0) > 0
    }

    /// Candidate Profile from the current inputs (metric), or nil until the basics are valid.
    /// Read by both the live BMR preview and the "changed" check.
    private var candidate: Profile? {
        guard basicValid, let sex, let ageYears = Int(age), let feetVal = Double(feet)
        else { return nil }
        let inchesVal = Double(inches) ?? 0
        return Profile(
            name: candidateName,
            sex: sex,
            ageYears: ageYears,
            heightCm: Units.ftInToCm(feet: feetVal, inches: inchesVal).rounded(),
            weightKg: liveWeightKg,
            createdAt: profile.createdAt
        )
    }

    /// Weight is intentionally absent from this comparison: it cannot be edited here, and including
    /// it would light up the Save button purely because WHOOP synced a new value in the background.
    private var changed: Bool {
        guard let candidate else { return false }
        return candidate.name != profile.name
            || candidate.sex != profile.sex
            || candidate.ageYears != profile.ageYears
            || candidate.heightCm != profile.heightCm
    }

    private var bmrText: String {
        Format.int(EnergyMath.computeBmr(candidate ?? profile))
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Sex binding animated at the call site so the segmented pill slides, leaving the shared
    /// `SegmentedChoice` untouched. No animation under Reduce Motion.
    private var animatedSex: Binding<Sex?> {
        Binding(
            get: { sex },
            set: { newValue in
                if reduceMotion {
                    sex = newValue
                } else {
                    withAnimation(Theme.Motion.stepTransition) { sex = newValue }
                }
            }
        )
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

                    SegmentedChoice<Sex>(
                        label: "Sex (for health reference ranges)",
                        options: [
                            .init(value: .female, label: "Female"),
                            .init(value: .male, label: "Male"),
                            .init(value: .other, label: "Other"),
                        ],
                        selection: animatedSex
                    )

                    FormField(
                        label: "Age (years)",
                        text: $age,
                        placeholder: "e.g. 34",
                        keyboard: .numberPad
                    )

                    HStack(spacing: Theme.Spacing.md) {
                        FormField(
                            label: "Height (ft)",
                            text: $feet,
                            placeholder: "5",
                            keyboard: .numberPad
                        )
                        FormField(
                            label: "(in)",
                            text: $inches,
                            placeholder: "10",
                            keyboard: .numberPad
                        )
                    }

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

    /// Changes whenever any editable field does, so one `onChange` can clear the "saved" confirmation.
    /// Weight is excluded: it is not editable here, so a WHOOP sync must not clear the confirmation.
    private var editSignature: String {
        "\(name)|\(sex?.rawValue ?? "")|\(age)|\(feet)|\(inches)"
    }

    private func save() {
        guard let candidate, changed else { return }
        // Explicit user edit (age / height / sex), so recompute now rather than waiting for Monday.
        appModel.updateProfile(candidate, recomputeGoals: true)
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
