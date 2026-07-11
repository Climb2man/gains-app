import SwiftUI

struct GoalCalculatorSheet: View {
    /// Profile to estimate from (sex/age/height/weight). `nil` if the about-you step is incomplete,
    /// in which case the sheet explains it needs those details.
    let profile: Profile?
    /// Called with the computed estimate when the user taps "Use this estimate".
    let onApply: (GoalCalculator.Result) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var activityIndex = GoalCalculator.ActivityLevel.allCases.firstIndex(of: .moderate) ?? 0
    @State private var goalIndex = GoalCalculator.GoalDirection.allCases.firstIndex(of: .maintain) ?? 0

    private var activity: GoalCalculator.ActivityLevel {
        GoalCalculator.ActivityLevel.allCases[activityIndex]
    }
    private var goal: GoalCalculator.GoalDirection {
        GoalCalculator.GoalDirection.allCases[goalIndex]
    }

    /// Estimate recomputed on every render from the current activity and goal.
    private var result: GoalCalculator.Result? {
        guard let profile else { return nil }
        return GoalCalculator.estimate(profile: profile, activity: activity, goal: goal)
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Estimate my goals", onClose: { dismiss() })
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.top, Theme.Spacing.lg)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    if let profile {
                        profileCard(profile)
                        activityCard
                        goalCard
                        if let result { estimateCard(result) }
                        AppButton(title: "Use this estimate", kind: .primary) {
                            if let result { onApply(result) }
                        }
                        .disabled(result == nil)
                        .opacity(result == nil ? 0.5 : 1)
                    } else {
                        SurfaceCard {
                            Txt(
                                "Add your details first. The estimate needs your sex, age, height, and weight.",
                                variant: .body, color: .labelSecondary
                            )
                        }
                    }

                    Txt(
                        "An estimate you can edit. It pre-fills your goals; you confirm them.",
                        variant: .footnote, color: .labelTertiary, center: true
                    )
                }
                .padding(Theme.Spacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.Colors.background)
    }

    private func profileCard(_ profile: Profile) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Txt("FROM YOUR PROFILE", variant: .sectionHeader, color: .labelSecondary)
                Txt(
                    "\(sexLabel(profile.sex)) · \(profile.ageYears) yrs · \(Format.feetInches(profile.heightCm)) · \(Format.int(Units.kgToLb(profile.weightKg))) lb",
                    variant: .body
                )
            }
        }
    }

    private var activityCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Txt("ACTIVITY LEVEL", variant: .sectionHeader, color: .labelSecondary)
                RadioPicker(options: activityLabels, selection: $activityIndex)
            }
        }
    }

    /// Picker row labels: each level's name plus its description, joined by a dot.
    private var activityLabels: [String] {
        GoalCalculator.ActivityLevel.allCases.map { "\($0.label) · \($0.description)" }
    }

    private var goalCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Txt("GOAL", variant: .sectionHeader, color: .labelSecondary)
                RadioPicker(
                    options: GoalCalculator.GoalDirection.allCases.map(\.label),
                    selection: $goalIndex
                )
            }
        }
    }

    private func estimateCard(_ result: GoalCalculator.Result) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Txt("YOUR ESTIMATE", variant: .sectionHeader, color: .labelSecondary)
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Text(Format.int(Double(result.calorieGoal)))
                        .font(Theme.Font.heroNumber)
                        .foregroundStyle(Theme.Colors.label)
                        .contentTransition(.numericText())
                    Txt("kcal/day", variant: .body, color: .labelSecondary)
                }
                MacroSplitBar(
                    proteinG: result.proteinGoal,
                    fatG: result.fatGoal,
                    carbsG: result.carbGoal
                )
                Txt(
                    "BMR \(Format.int(Double(result.bmr))) · maintenance \(Format.int(Double(result.tdee))) kcal (Mifflin St Jeor).",
                    variant: .footnote, color: .labelTertiary
                )
            }
        }
        .cardShadow(Theme.Shadow.cardElevated)
    }

    private func sexLabel(_ sex: Sex) -> String {
        switch sex {
        case .male: return "Male"
        case .female: return "Female"
        case .other: return "Other"
        }
    }
}

#if DEBUG
#Preview("GoalCalculator") {
    Color.clear.sheet(isPresented: .constant(true)) {
        GoalCalculatorSheet(
            profile: Profile(
                name: nil, sex: .male, ageYears: 20, heightCm: 178, weightKg: 93.4,
                createdAt: "2026-01-01T00:00:00.000Z"
            ),
            onApply: { _ in }
        )
    }
}
#endif
