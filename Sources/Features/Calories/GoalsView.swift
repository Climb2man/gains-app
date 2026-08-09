import SwiftUI

/// Goal setting, reduced to the only two decisions the Bigger Leaner Stronger method needs:
/// what you are doing (cut / maintain / lean bulk) and how much you train (hours per week).
///
/// Calories and macros are DERIVED and cannot be typed. Everything else the maths needs — weight,
/// height, age, sex — comes from WHOOP. The daily step target is the one number still set by hand,
/// because it is not part of the calorie model and WHOOP exposes no step goal to read.
struct GoalsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    let goals: Goals
    let onSave: (Goals) -> Void

    @State private var goal: GoalCalculator.GoalDirection?
    @State private var activity: GoalCalculator.ActivityLevel?
    @State private var steps: Int
    /// How AI estimates lean. Chosen once in onboarding and previously unreachable afterwards.
    @State private var bias: CalorieBias = .balanced
    /// 7-day mean WHOOP day-strain, used only to suggest an activity band. nil until loaded/unlinked.
    @State private var avgStrain: Double?

    init(goals: Goals, onSave: @escaping (Goals) -> Void) {
        self.goals = goals
        self.onSave = onSave
        _steps = State(initialValue: goals.stepsGoal)
    }

    /// The activity WHOOP's recent strain points at, if we have strain at all.
    private var suggested: GoalCalculator.ActivityLevel? {
        avgStrain.map(GoalCalculator.suggestedActivity(avgDayStrain:))
    }

    /// Computed from the current weight — the same value the weekly refresh will use, so the number
    /// previewed here is the number that gets applied.
    private var estimate: GoalCalculator.Result? {
        guard let profile = appModel.profile, let goal, let activity else { return nil }
        return GoalCalculator.estimate(profile: profile, activity: activity, goal: goal)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Txt("Your goals", variant: .largeTitle)
                    Txt("Calories and macros are worked out from these two.",
                        variant: .body, color: .labelSecondary)

                    goalSection
                    activitySection

                    if let estimate {
                        resultCard(estimate)
                    } else {
                        Card {
                            Txt(appModel.profile == nil
                                ? "Finish setting up your profile first."
                                : "Choose a goal and an activity level to see your targets.",
                                variant: .footnote, color: .labelTertiary)
                        }
                    }

                    stepsField
                    CalorieBiasCard(selection: $bias)

                    AppButton(title: "Save goals", kind: .primary) { save() }
                        .opacity(estimate == nil ? 0.5 : 1)
                        .disabled(estimate == nil)

                    Txt("Targets refresh Mondays.",
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
            .onAppear {
                seedFromStoredRecipe()
                bias = appModel.foodLogSettings.bias
            }
            .task { avgStrain = await appModel.whoopStrainAverage(days: 7) }
        }
    }

    // MARK: goal

    private var goalSection: some View {
        Card {
            Txt("GOAL", variant: .sectionHeader, color: .labelSecondary)
            ForEach(GoalCalculator.GoalDirection.allCases) { option in
                choiceRow(
                    title: option.label,
                    subtitle: option.description,
                    selected: goal == option,
                    badge: nil
                ) { goal = option }
                if option != GoalCalculator.GoalDirection.allCases.last { HairlineDivider() }
            }
        }
    }

    // MARK: activity

    private var activitySection: some View {
        Card {
            HStack {
                Txt("ACTIVITY", variant: .sectionHeader, color: .labelSecondary)
                Spacer(minLength: 0)
                if let avgStrain {
                    Txt("strain \(Format.oneDecimal(avgStrain))",
                        variant: .footnote, color: .labelTertiary)
                }
            }
            ForEach(GoalCalculator.ActivityLevel.allCases) { option in
                choiceRow(
                    title: option.label,
                    subtitle: "\(option.hoursPerWeek) · \(option.description)",
                    selected: activity == option,
                    badge: suggested == option ? "WHOOP suggests" : nil
                ) { activity = option }
                if option != GoalCalculator.ActivityLevel.allCases.last { HairlineDivider() }
            }
            if avgStrain == nil {
                Txt("Connect WHOOP for a suggestion based on your recent strain.",
                    variant: .footnote, color: .labelTertiary)
            }
        }
    }

    /// One selectable row. Kept deliberately plain: the whole row is the hit target, and selection is
    /// shown by a checkmark rather than colour alone.
    private func choiceRow(
        title: String, subtitle: String, selected: Bool, badge: String?, tap: @escaping () -> Void
    ) -> some View {
        Button(action: tap) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Txt(title, variant: .bodyEmphasized)
                        if let badge {
                            Txt(badge, variant: .footnote, color: .tint)
                                .padding(.horizontal, Theme.Spacing.sm)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Theme.Colors.fieldBackground))
                        }
                    }
                    Txt(subtitle, variant: .footnote, color: .labelTertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? Theme.Colors.tint : Theme.Colors.labelTertiary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, Theme.Spacing.xs)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: result

    private func resultCard(_ r: GoalCalculator.Result) -> some View {
        let p = Double(r.proteinGoal) * CaloriesSupport.kcalPerProteinG
        let c = Double(r.carbGoal) * CaloriesSupport.kcalPerCarbG
        let f = Double(r.fatGoal) * CaloriesSupport.kcalPerFatG

        return Card {
            HStack(spacing: Theme.Spacing.xl) {
                MacroDonut(
                    segments: [
                        (value: p, color: Theme.Chart.protein, label: "Protein"),
                        (value: c, color: Theme.Chart.carbs, label: "Carbs"),
                        (value: f, color: Theme.Chart.fat, label: "Fat"),
                    ],
                    size: 116, strokeWidth: 14,
                    centerLabel: Format.int(Double(r.calorieGoal)),
                    centerSubLabel: "kcal"
                )
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Txt("YOUR TARGETS", variant: .sectionHeader, color: .labelSecondary)
                    macroRow("Protein", grams: r.proteinGoal, color: Theme.Chart.protein)
                    macroRow("Carbs", grams: r.carbGoal, color: Theme.Chart.carbs)
                    macroRow("Fat", grams: r.fatGoal, color: Theme.Chart.fat)
                }
                Spacer(minLength: 0)
            }
            Txt("BMR \(r.bmr) · maintenance \(r.tdee) kcal",
                variant: .footnote, color: .labelTertiary)
        }
    }

    private func macroRow(_ label: String, grams: Int, color: Color) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Circle().fill(color).frame(width: 9, height: 9)
            Txt(label, variant: .subhead)
            Spacer(minLength: 0)
            Txt("\(grams) g", variant: .subhead, color: .labelSecondary)
        }
    }

    private var stepsField: some View {
        Card {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Chart.activity)
                Txt("Daily steps", variant: .bodyEmphasized)
                Spacer(minLength: 0)
                NumberStepper(value: $steps, range: 0...50_000, step: 1_000, unit: "steps")
                    .contentTransition(.numericText())
            }
            Txt("The one target you set yourself — it isn't part of the calorie maths.",
                variant: .footnote, color: .labelTertiary)
        }
    }

    // MARK: state

    /// Restore the previous choice. A recipe written by the OLD goal model (directions like
    /// "lose1") will not resolve to any current case, so both pickers simply start empty and the
    /// existing calorie targets stay untouched until a fresh choice is made.
    private func seedFromStoredRecipe() {
        guard let recipe = appModel.nutritionStore.goalRecipe else { return }
        goal = GoalCalculator.GoalDirection(rawValue: recipe.direction)
        activity = GoalCalculator.ActivityLevel(rawValue: recipe.activity)
    }

    private func save() {
        guard let estimate else { return }
        onSave(Goals(
            calorieGoal: Double(estimate.calorieGoal),
            proteinGoal: Double(estimate.proteinGoal),
            fatGoal: Double(estimate.fatGoal),
            carbGoal: Double(estimate.carbGoal),
            stepsGoal: steps
        ))
        // autoAdjust is always true now: with no manual entry there is nothing to preserve, and the
        // weekly refresh is the only thing that keeps targets in step with a changing body weight.
        appModel.nutritionStore.setGoalRecipe(
            GoalRecipe(activity: estimate.activity.rawValue, direction: estimate.goal.rawValue),
            autoAdjust: true
        )
        appModel.foodLogSettings.setBias(bias)
        dismiss()
    }
}
