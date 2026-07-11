import SwiftUI

@MainActor
struct SavedMealsScreen: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingAdd = false
    /// The meal being edited (drives the edit sheet), if any.
    @State private var editingMeal: FoodShortcut?
    /// Search text filtering the list by nickname.
    @State private var searchText = ""
    /// Transient "Logged ✓" confirmation after a re-log.
    @State private var loggedNote: String?

    private var savedFoods: SavedFoodsStore { appModel.savedFoods }

    /// Saved meals, filtered by the search text (pinned-first ordering preserved by the store).
    private var meals: [FoodShortcut] {
        let all = savedFoods.shortcuts
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? all : all.filter { $0.nickname.localizedStandardContains(query) }
    }

    var body: some View {
        Group {
            if savedFoods.shortcuts.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(Theme.Colors.background)
        .navigationTitle("Saved meals")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done", action: dismiss.callAsFunction)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: {
                    Image(systemName: "plus").foregroundStyle(Theme.Colors.tint)
                }
                .accessibilityLabel("Add custom meal")
            }
        }
        .sheet(isPresented: $showingAdd) {
            CustomMealSheet(savedFoods: savedFoods)
        }
        .sheet(item: $editingMeal) { meal in
            CustomMealSheet(savedFoods: savedFoods, editing: meal)
        }
        .overlay(alignment: .bottom) {
            if let note = loggedNote {
                Txt(note, variant: .footnote, color: .onTint)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Capsule().fill(Theme.Colors.tint))
                    .padding(.bottom, Theme.Spacing.xl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(meals) { meal in
                    HStack(spacing: Theme.Spacing.sm) {
                        Button { relog(meal) } label: { row(meal) }
                            .buttonStyle(.plain)
                        rowMenu(meal)
                    }
                    .listRowInsets(EdgeInsets(top: Theme.Spacing.sm, leading: Theme.Spacing.lg,
                                              bottom: Theme.Spacing.sm, trailing: Theme.Spacing.lg))
                    .listRowBackground(Theme.Colors.surface)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { savedFoods.remove(id: meal.id) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button { editingMeal = meal } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(Theme.Colors.tint)
                    }
                    .swipeActions(edge: .leading) {
                        Button { savedFoods.setPinned(id: meal.id, !meal.pinned) } label: {
                            Label(meal.pinned ? "Unpin" : "Pin", systemImage: meal.pinned ? "pin.slash" : "pin")
                        }
                        .tint(Theme.Colors.warning)
                    }
                }
            } footer: {
                Txt("Tap a meal to log it. ••• for a half/double portion, edit, or pin. Swipe to delete. These stay on this device.",
                    variant: .footnote, color: .labelTertiary)
                    .padding(.top, Theme.Spacing.sm)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search saved meals")
        .overlay {
            if meals.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    private func row(_ meal: FoodShortcut) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.xs) {
                    if meal.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Colors.warning)
                            .accessibilityLabel("Pinned")
                    }
                    Txt(meal.nickname, variant: .bodyEmphasized).lineLimit(1)
                }
                Txt(subtitle(meal), variant: .footnote, color: .labelSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Theme.Colors.tint)
        }
        .contentShape(.rect)
    }

    /// The ••• menu: scaled-portion re-logs, edit, pin/unpin, delete.
    private func rowMenu(_ meal: FoodShortcut) -> some View {
        Menu {
            Section("Log a portion") {
                Button { relog(meal, factor: 0.5) } label: { Label("Half (½×)", systemImage: "circle.lefthalf.filled") }
                Button { relog(meal, factor: 1.5) } label: { Label("One and a half (1½×)", systemImage: "circle.bottomhalf.filled") }
                Button { relog(meal, factor: 2) } label: { Label("Double (2×)", systemImage: "circle.fill") }
            }
            Button { editingMeal = meal } label: { Label("Edit", systemImage: "pencil") }
            Button { savedFoods.setPinned(id: meal.id, !meal.pinned) } label: {
                Label(meal.pinned ? "Unpin" : "Pin to top", systemImage: meal.pinned ? "pin.slash" : "pin")
            }
            Button(role: .destructive) { savedFoods.remove(id: meal.id) } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 20))
                .foregroundStyle(Theme.Colors.labelSecondary)
                .frame(width: 32, height: 32)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More options for \(meal.nickname)")
    }

    private func subtitle(_ meal: FoodShortcut) -> String {
        let p = meal.items.reduce(0) { $0 + $1.proteinG }
        let c = meal.items.reduce(0) { $0 + $1.carbsG }
        let f = meal.items.reduce(0) { $0 + $1.fatG }
        return "\(Format.int(meal.totalCalories)) kcal · " + FoodLogFormat.macroLine(protein: p, carbs: c, fat: f)
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                EmptyStateCard(
                    icon: "bookmark",
                    title: "No saved meals yet",
                    message: "Save a meal from your food log (swipe a line → Save), or add a custom one with the + button."
                )
                Button { showingAdd = true } label: {
                    Txt("Add custom meal", variant: .bodyEmphasized, color: .tint)
                }
                .buttonStyle(.plain)
            }
            .padding(Theme.Spacing.lg)
        }
    }

    /// Re-log a saved meal to today, optionally scaled by a portion factor (½× / 1½× / 2×). No AI:
    /// the snapshot's items are scaled in code and re-inserted with fresh ids.
    private func relog(_ meal: FoodShortcut, factor: Double = 1) {
        let items = meal.items.map { $0.scaled(by: factor) }
        appModel.foodLog.logShortcut(FoodShortcut(
            nickname: meal.nickname, items: items, source: "saved",
            createdAt: FoodLogStore.isoNow(), updatedAt: FoodLogStore.isoNow()
        ))
        savedFoods.bumpUse(id: meal.id)
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        let prefix = factor == 1 ? "" : "\(Self.portionLabel(factor)) "
        withAnimation { loggedNote = "Logged \(prefix)\(meal.nickname) to today" }
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation { loggedNote = nil }
        }
    }

    private static func portionLabel(_ factor: Double) -> String {
        switch factor {
        case 0.5: "½×"
        case 1.5: "1½×"
        case 2: "2×"
        default: "\(Format.int(factor))×"
        }
    }
}

private struct CustomMealSheet: View {
    let savedFoods: SavedFoodsStore
    /// When set, the sheet edits this meal in place; when nil, it creates a new one.
    let editing: FoodShortcut?
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var calories: String
    @State private var protein: String
    @State private var carbs: String
    @State private var fat: String

    /// Prefill from `editing` in the initializer so fields are populated before the first body render
    /// (avoids an onAppear flicker). Uses a plain integer string, not `Format.int`: `Format.int` groups
    /// thousands ("1,116"), which `Double` then parses to nil and would silently zero the field on save.
    /// New meals start blank.
    init(savedFoods: SavedFoodsStore, editing: FoodShortcut? = nil) {
        self.savedFoods = savedFoods
        self.editing = editing
        func plain(_ value: Double) -> String { value > 0 ? String(Int(value.rounded())) : "" }
        _name = State(initialValue: editing?.nickname ?? "")
        _calories = State(initialValue: plain(editing?.items.reduce(0) { $0 + $1.calories } ?? 0))
        _protein = State(initialValue: plain(editing?.items.reduce(0) { $0 + $1.proteinG } ?? 0))
        _carbs = State(initialValue: plain(editing?.items.reduce(0) { $0 + $1.carbsG } ?? 0))
        _fat = State(initialValue: plain(editing?.items.reduce(0) { $0 + $1.fatG } ?? 0))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    FormField(label: "Meal name", text: $name, placeholder: "e.g. My usual breakfast",
                               autocap: .sentences)
                    Card {
                        HStack(spacing: Theme.Spacing.md) {
                            field("Calories", $calories)
                            field("Protein g", $protein)
                        }
                        HStack(spacing: Theme.Spacing.md) {
                            field("Carbs g", $carbs)
                            field("Fat g", $fat)
                        }
                    }
                    if let editing, editing.items.count > 1 {
                        Txt("Editing combines this meal's \(editing.items.count) items into one saved total.",
                            variant: .footnote, color: .warning, center: true)
                    }
                    AppButton(title: editing == nil ? "Save meal" : "Save changes", kind: .primary) { save() }
                        .disabled(!canSave)
                    Txt("Numbers you enter are saved exactly. You can re-log this meal in one tap.",
                        variant: .footnote, color: .labelTertiary, center: true)
                }
                .padding(Theme.Spacing.xl)
            }
            .background(Theme.Colors.background)
            .navigationTitle(editing == nil ? "Add custom meal" : "Edit meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
            }
        }
    }

    private func field(_ label: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Txt(label, variant: .footnote, color: .labelSecondary)
            TextField(label, text: text)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Colors.label)
                .keyboardType(.decimalPad)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(Theme.Colors.fieldBackground))
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (Double(calories) ?? 0) > 0
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = LoggedFoodItem(
            name: trimmed,
            calories: Double(calories) ?? 0,
            proteinG: Double(protein) ?? 0,
            carbsG: Double(carbs) ?? 0,
            fatG: Double(fat) ?? 0,
            assumptions: editing == nil ? "Custom meal you saved." : "Custom meal you edited.",
            confidenceScore: 100,
            provenance: .stated
        )
        if let editing {
            savedFoods.update(id: editing.id, nickname: trimmed, items: [item])
        } else {
            savedFoods.save(nickname: trimmed, items: [item], source: "custom")
        }
        dismiss()
    }
}

#if DEBUG
#Preview("Saved meals") {
    NavigationStack { SavedMealsScreen() }
        .environment(AppModel.sample)
}
#endif
