import SwiftUI

struct EditFoodSheet: View {
    let entry: FoodJournalEntry
    let bias: CalorieBias
    /// Re-type path: hand the new text back to the store (cheap portion path when applicable).
    let onRetype: (String) -> Void
    /// One-tap correction path: persist a hand-corrected item directly (no AI).
    let onCorrectItem: (LoggedFoodItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    retypeSection
                    if !entry.items.isEmpty && !entry.isWaterOnly {
                        correctionSection
                    }
                    Txt("All numbers are estimates you confirm. The bias is disclosed: \(bias.disclosure)",
                        variant: .footnote, color: .labelTertiary, center: true)
                }
                .padding(Theme.Spacing.xl)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Edit line")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
            .onAppear { if text.isEmpty { text = entry.foodText } }
        }
    }

    private var retypeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Txt("RE-TYPE IN PLAIN ENGLISH", variant: .sectionHeader, color: .labelSecondary)
            Field(label: "What did you eat?", text: $text,
                  placeholder: "e.g. half a chicken burrito bowl")
            PrimaryButton(title: "Re-estimate this line", disabled: !canRetype) {
                onRetype(text.trimmingCharacters(in: .whitespacesAndNewlines))
                dismiss()
            }
            Txt("A portion change (“half a …”, “a couple bites”) uses the cheap path · no web search.",
                variant: .footnote, color: .labelTertiary)
        }
    }

    private var correctionSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Txt("OR CORRECT THE NUMBERS", variant: .sectionHeader, color: .labelSecondary)
            ForEach(entry.items) { item in
                ItemCorrectionRow(item: item, onSave: { corrected in
                    onCorrectItem(corrected)
                    dismiss()
                })
            }
        }
    }

    private var canRetype: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != entry.foodText
    }
}

private struct ItemCorrectionRow: View {
    let item: LoggedFoodItem
    let onSave: (LoggedFoodItem) -> Void

    @State private var calories: String
    @State private var protein: String
    @State private var carbs: String
    @State private var fat: String

    init(item: LoggedFoodItem, onSave: @escaping (LoggedFoodItem) -> Void) {
        self.item = item
        self.onSave = onSave
        _calories = State(initialValue: Self.fmt(item.calories))
        _protein = State(initialValue: Self.fmt(item.proteinG))
        _carbs = State(initialValue: Self.fmt(item.carbsG))
        _fat = State(initialValue: Self.fmt(item.fatG))
    }

    var body: some View {
        Card {
            Txt(item.name, variant: .bodyEmphasized).lineLimit(1)
            HStack(spacing: Theme.Spacing.md) {
                NumberField(label: "Calories", text: $calories)
                NumberField(label: "Protein g", text: $protein)
            }
            HStack(spacing: Theme.Spacing.md) {
                NumberField(label: "Carbs g", text: $carbs)
                NumberField(label: "Fat g", text: $fat)
            }
            SecondaryButton(title: "Save correction") {
                var corrected = item
                corrected.calories = Double(calories) ?? item.calories
                corrected.proteinG = Double(protein) ?? item.proteinG
                corrected.carbsG = Double(carbs) ?? item.carbsG
                corrected.fatG = Double(fat) ?? item.fatG
                corrected.confidenceScore = 100
                corrected.assumptions = "Corrected by you."
                onSave(corrected)
            }
        }
    }

    /// Whole numbers show without a trailing ".0"; fractional values keep their decimals.
    private static func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }
}

private struct NumberField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Txt(label, variant: .footnote, color: .labelSecondary)
            TextField(label, text: $text)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Colors.label)
                .keyboardType(.decimalPad)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .fill(Theme.Colors.fieldBackground)
                )
        }
    }
}

#if DEBUG
#Preview("Edit food") {
    EditFoodSheet(
        entry: FoodJournalEntry(
            foodText: "chicken burrito bowl",
            items: [LoggedFoodItem(name: "Chicken burrito bowl", calories: 720, proteinG: 42,
                                   carbsG: 78, fatG: 26, confidenceScore: 62)],
            status: .resolved, loggedAt: FoodLogStore.isoNow()),
        bias: .overestimateHigh,
        onRetype: { _ in }, onCorrectItem: { _ in }
    )
}
#endif
