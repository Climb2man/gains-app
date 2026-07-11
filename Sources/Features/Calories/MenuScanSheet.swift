import SwiftUI

struct MenuScanSheet: View {
    let candidates: [MenuItemCandidate]
    /// Confirm the picks; each runs through the core pipeline for nutrition.
    let onConfirm: ([MenuItemCandidate]) -> Void
    let onCancel: () -> Void

    @State private var selected: Set<String> = []

    var body: some View {
        NavigationStack {
            MenuSectionList(
                sections: sections,
                selected: selected,
                onToggle: toggle
            )
            .background(Theme.Colors.background)
            .navigationTitle("What did you eat?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add", action: confirm).disabled(selected.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) { confirmBar }
        }
    }

    /// Candidates grouped by their menu section, sections in first-appearance order; an unsectioned
    /// menu collapses into one "Menu" group so the list still renders.
    private var sections: [MenuSection] {
        var order: [String] = []
        var buckets: [String: [MenuItemCandidate]] = [:]
        for candidate in candidates {
            let key = candidate.section?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (key?.isEmpty == false) ? (key ?? "Menu") : "Menu"
            if buckets[title] == nil { order.append(title) }
            buckets[title, default: []].append(candidate)
        }
        return order.map { MenuSection(title: $0, items: buckets[$0] ?? []) }
    }

    private var confirmBar: some View {
        VStack(spacing: 0) {
            HairlineDivider()
            PrimaryButton(title: confirmTitle, disabled: selected.isEmpty, action: confirm)
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.md)
        }
        .background(Theme.Colors.surface)
    }

    private var confirmTitle: String {
        guard !selected.isEmpty else { return "Pick the dishes you ate" }
        let suffix = selected.count == 1 ? "dish" : "dishes"
        return "Add \(selected.count) \(suffix)"
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func confirm() {
        let picks = candidates.filter { selected.contains($0.id) }
        guard !picks.isEmpty else { return }
        onConfirm(picks)
    }
}

/// One menu section: a heading + its dish candidates. Identifiable by title (first-appearance unique).
struct MenuSection: Identifiable {
    let title: String
    let items: [MenuItemCandidate]
    var id: String { title }
}

/// The grouped, multi-select list of menu candidates. Extracted so the sheet body type-checks quickly.
private struct MenuSectionList: View {
    let sections: [MenuSection]
    let selected: Set<String>
    let onToggle: (String) -> Void

    var body: some View {
        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.items) { candidate in
                        MenuCandidateRow(
                            candidate: candidate,
                            isSelected: selected.contains(candidate.id),
                            onToggle: { onToggle(candidate.id) }
                        )
                        .listRowBackground(Theme.Colors.surface)
                    }
                } header: {
                    Txt(section.title, variant: .footnote, color: .labelSecondary)
                }
            }
            Section {
                Txt("Each dish you pick is estimated on its own through the usual pipeline. Numbers are editable estimates.",
                    variant: .footnote, color: .labelTertiary)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }
}

private struct MenuCandidateRow: View {
    let candidate: MenuItemCandidate
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Theme.Colors.tint : Theme.Colors.labelTertiary)
                Txt(candidate.name, variant: .body).lineLimit(2)
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(candidate.name)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Double tap to toggle whether you ate this")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#if DEBUG
#Preview("Menu scan") {
    MenuScanSheet(
        candidates: [
            MenuItemCandidate(name: "Carne Asada Taco", section: "Tacos"),
            MenuItemCandidate(name: "Al Pastor Taco", section: "Tacos"),
            MenuItemCandidate(name: "Chicken Quesadilla", section: "Quesadillas"),
            MenuItemCandidate(name: "Chips and Guacamole", section: "Sides"),
            MenuItemCandidate(name: "Horchata", section: "Drinks"),
        ],
        onConfirm: { _ in }, onCancel: {}
    )
}
#endif
