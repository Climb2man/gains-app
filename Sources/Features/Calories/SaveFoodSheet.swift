import SwiftUI

struct SaveFoodSheet: View {
    let entry: FoodJournalEntry
    @Bindable var savedFoods: SavedFoodsStore
    @Environment(\.dismiss) private var dismiss

    @State private var nickname: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Field(
                        label: "Nickname",
                        text: $nickname,
                        placeholder: "e.g. regular Chipotle order"
                    )

                    summaryCard

                    if exists {
                        Txt("A saved food with this nickname already exists. Saving will update its macros.",
                            variant: .footnote, color: .warning)
                    }

                    PrimaryButton(title: exists ? "Update saved food" : "Save food", disabled: !canSave) {
                        save()
                    }

                    Txt("Saved foods re-log instantly with no AI call. Macros stay editable estimates.",
                        variant: .footnote, color: .labelTertiary, center: true)
                }
                .padding(Theme.Spacing.xl)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Save & nickname")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
            }
            .onAppear {
                if nickname.isEmpty { nickname = entry.displayTitle }
            }
        }
    }

    private var summaryCard: some View {
        Card {
            Txt("WHAT YOU'RE SAVING", variant: .sectionHeader, color: .labelSecondary)
            ForEach(entry.items) { item in
                HStack {
                    Txt(item.name, variant: .body).lineLimit(1)
                    Spacer(minLength: Theme.Spacing.sm)
                    Txt(item.isWaterEntry ? FoodLogFormat.water(item.waterMilliliters)
                                          : "\(Format.int(item.calories)) kcal",
                        variant: .footnote, color: .labelSecondary)
                }
            }
        }
    }

    private var canSave: Bool {
        !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !entry.items.isEmpty
    }

    private var exists: Bool {
        savedFoods.exists(nickname: nickname)
    }

    private func save() {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        savedFoods.save(nickname: trimmed, items: entry.items)
        dismiss()
    }
}

#if DEBUG
#Preview("Save food") {
    SaveFoodSheet(
        entry: FoodJournalEntry(
            foodText: "chicken burrito bowl",
            items: [LoggedFoodItem(name: "Chicken burrito bowl", calories: 720, proteinG: 42,
                                   carbsG: 78, fatG: 26)],
            status: .resolved, loggedAt: FoodLogStore.isoNow()),
        savedFoods: SavedFoodsStore(store: UserDefaultsStore(
            defaults: UserDefaults(suiteName: "preview.savefood") ?? .standard))
    )
}
#endif
