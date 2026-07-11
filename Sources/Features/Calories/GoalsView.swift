import SwiftUI

struct GoalsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    let goals: Goals
    let onSave: (Goals) -> Void

    @State private var calorie: String
    @State private var protein: String
    @State private var fat: String
    @State private var carb: String
    /// Daily step target, a first-class goal alongside the macros. Int-backed so `NumberStepper` binds
    /// directly (the macros stay text fields).
    @State private var steps: Int
    @State private var calcOpen = false
    /// The calculator inputs behind the current numbers, seeded from the store and refreshed when the
    /// user applies the calculator. Required for the auto-adjust switch to work.
    @State private var appliedRecipe: GoalRecipe?
    /// Auto-adjust switch: recalc calories/macros from the current weight (via the recipe) whenever the
    /// weight changes. Persisted on save.
    @State private var autoAdjust = false

    init(goals: Goals, onSave: @escaping (Goals) -> Void) {
        self.goals = goals
        self.onSave = onSave
        _calorie = State(initialValue: Self.intString(goals.calorieGoal))
        _protein = State(initialValue: Self.intString(goals.proteinGoal))
        _fat = State(initialValue: Self.intString(goals.fatGoal))
        _carb = State(initialValue: Self.intString(goals.carbGoal))
        _steps = State(initialValue: goals.stepsGoal)
    }

    private var calorieNum: Int? { Int(calorie.trimmingCharacters(in: .whitespaces)) }
    private var proteinNum: Int? { Int(protein.trimmingCharacters(in: .whitespaces)) }
    private var fatNum: Int? { Int(fat.trimmingCharacters(in: .whitespaces)) }
    private var carbNum: Int? { Int(carb.trimmingCharacters(in: .whitespaces)) }

    private var allValid: Bool {
        guard let c = calorieNum, c > 0,
              let p = proteinNum, p >= 0,
              let f = fatNum, f >= 0,
              let cb = carbNum, cb >= 0 else { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    HStack {
                        Txt("Your goals", variant: .largeTitle)
                        Spacer(minLength: 0)
                        Button { calcOpen = true } label: {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 15))
                                Txt("Help me", variant: .subhead, color: .tint)
                            }
                            .foregroundStyle(Theme.Colors.tint)
                            .padding(.vertical, Theme.Spacing.sm)
                            .padding(.horizontal, Theme.Spacing.md)
                            .background(Capsule().fill(Theme.Colors.fieldBackground))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Help me set my goal")
                    }

                    Txt("Set your daily targets. Tap the sparkles for an estimate, then edit anything and save.",
                        variant: .body, color: .labelSecondary)

                    macroPreview

                    Card {
                        Field(label: "Daily calories (kcal)", text: $calorie,
                              placeholder: "e.g. 2200", keyboard: .numberPad)
                        Txt("Your headline daily target.", variant: .footnote, color: .labelTertiary)
                    }

                    macroField(MacroCopy.protein, text: $protein, placeholder: "e.g. 160")
                    macroField(MacroCopy.fat, text: $fat, placeholder: "e.g. 73")
                    macroField(MacroCopy.carb, text: $carb, placeholder: "e.g. 206")

                    stepsField

                    if appliedRecipe != nil {
                        Card {
                            Toggle(isOn: $autoAdjust) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Txt("Auto-adjust with weight", variant: .bodyEmphasized)
                                    Txt(
                                        "Recalculates calories and macros from your current weight "
                                            + "(using your calculator settings) whenever it changes. "
                                            + "Past days keep the goals they were judged against.",
                                        variant: .footnote, color: .labelTertiary
                                    )
                                }
                            }
                            .tint(Theme.Colors.tint)
                        }
                    }

                    AppButton(title: "Save goals", kind: .primary) {
                        guard allValid,
                              let c = calorieNum, let p = proteinNum,
                              let f = fatNum, let cb = carbNum else { return }
                        onSave(Goals(
                            calorieGoal: Double(c), proteinGoal: Double(p),
                            fatGoal: Double(f), carbGoal: Double(cb),
                            stepsGoal: steps
                        ))
                        appModel.nutritionStore.setGoalRecipe(appliedRecipe, autoAdjust: autoAdjust)
                        dismiss()
                    }
                    .opacity(allValid ? 1 : 0.5)
                    .disabled(!allValid)

                    Txt("Goals are targets you set.",
                        variant: .footnote, color: .labelTertiary, center: true)
                }
                .padding(Theme.Spacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
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
            .sheet(isPresented: $calcOpen) {
                GoalCalculatorSheet(profile: appModel.profile) { result in
                    calorie = String(result.calorieGoal)
                    protein = String(result.proteinGoal)
                    fat = String(result.fatGoal)
                    carb = String(result.carbGoal)
                    appliedRecipe = GoalRecipe(
                        activity: result.activity.rawValue, direction: result.goal.rawValue
                    )
                    autoAdjust = true
                    calcOpen = false
                }
                .presentationDragIndicator(.visible)
            }
            .onAppear {
                appliedRecipe = appModel.nutritionStore.goalRecipe
                autoAdjust = appModel.nutritionStore.autoAdjustsGoals
            }
        }
    }

    /// Live MacroDonut of macro calories from the current field values (Atwater). Updates as the fields
    /// change so the energy split previews while tuning the goal numbers.
    private var macroPreview: some View {
        let p = Double(proteinNum ?? 0) * CaloriesSupport.kcalPerProteinG
        let c = Double(carbNum ?? 0) * CaloriesSupport.kcalPerCarbG
        let f = Double(fatNum ?? 0) * CaloriesSupport.kcalPerFatG
        let macroCals = p + c + f
        let hasData = macroCals > 0

        return Card {
            HStack(spacing: Theme.Spacing.xl) {
                MacroDonut(
                    segments: [
                        (value: p, color: Theme.Chart.protein, label: "Protein"),
                        (value: c, color: Theme.Chart.carbs, label: "Carbs"),
                        (value: f, color: Theme.Chart.fat, label: "Fat"),
                    ],
                    size: 116, strokeWidth: 14,
                    centerLabel: hasData ? Format.int(macroCals) : "–",
                    centerSubLabel: hasData ? "kcal" : "set macros"
                )
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Txt("MACRO SPLIT", variant: .sectionHeader, color: .labelSecondary)
                    previewRow("Protein", grams: proteinNum, color: Theme.Chart.protein)
                    previewRow("Carbs", grams: carbNum, color: Theme.Chart.carbs)
                    previewRow("Fat", grams: fatNum, color: Theme.Chart.fat)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func previewRow(_ label: String, grams: Int?, color: Color) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Circle().fill(color).frame(width: 9, height: 9)
            Txt(label, variant: .subhead)
            Spacer(minLength: 0)
            Txt("\(grams ?? 0) g", variant: .subhead, color: .labelSecondary)
        }
    }

    private var stepsField: some View {
        Card {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Chart.activity)
                Circle().fill(Theme.Chart.activity).frame(width: 9, height: 9)
                Txt("Daily steps", variant: .bodyEmphasized)
                Spacer(minLength: 0)
                NumberStepper(value: $steps, range: 0...50_000, step: 1_000, unit: "steps")
                    .contentTransition(.numericText())
            }
            Txt("A simple daily movement target. Progress comes from your day's step count.",
                variant: .footnote, color: .labelTertiary)
        }
    }

    private func macroField(_ copy: MacroCopy, text: Binding<String>, placeholder: String) -> some View {
        Card {
            HStack {
                Txt(copy.title, variant: .bodyEmphasized)
                Spacer(minLength: 0)
                Txt(copy.density, variant: .footnote, color: .labelSecondary)
            }
            Field(label: "\(copy.title) (g/day)", text: text,
                  placeholder: placeholder, keyboard: .numberPad)
            Txt(copy.why, variant: .footnote, color: .labelTertiary)
        }
    }

    /// Whole-number display string for a goal value (goals are stored as Double, edited as integers).
    private static func intString(_ value: Double) -> String {
        String(Int(value.rounded()))
    }
}
