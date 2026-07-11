import SwiftUI

struct FoodComposer: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    /// Saved meals shown as quick-add chips, already filtered by the parent to match `text`. Empty field
    /// shows the full set.
    let shortcuts: [FoodShortcut]
    /// Recent meals shown as quick-add chips, already filtered and deduped against `shortcuts`.
    let recents: [RecentMeal]
    let onSubmit: () -> Void
    let onLogShortcut: (FoodShortcut) -> Void
    let onLogRecent: (RecentMeal) -> Void
    /// Open the on-device barcode scanner (scan a product → log from Open Food Facts).
    let onScanBarcode: () -> Void
    /// Open the Recent history screen (the clock button): recently logged meals, re-loggable in one tap.
    /// When nil the button just focuses the field (legacy fallback).
    var onOpenRecents: (() -> Void)? = nil

    /// Whether the chip row has anything to show given the filtered inputs. Drives whether the row
    /// reserves height: when nothing matches, it collapses instead of leaving a dead 66pt gap above the
    /// keyboard.
    private var hasChips: Bool { !shortcuts.isEmpty || !recents.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            if isFocused.wrappedValue && hasChips {
                QuickAddChips(
                    shortcuts: shortcuts,
                    recents: recents,
                    onLogShortcut: onLogShortcut,
                    onLogRecent: onLogRecent
                )
                .frame(height: 66)
                HairlineDivider()
            }
            inputBar
        }
        .background(Theme.Colors.surface)
        .overlay(alignment: .top) { HairlineDivider() }
    }

    private var inputBar: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button {
                if let onOpenRecents { onOpenRecents() } else { isFocused.wrappedValue = true }
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.Colors.labelSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Recent meals")

            TextField("Add a line: “chicken bowl”, “16 oz water”…", text: $text, axis: .vertical)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Colors.label)
                .lineLimit(1...4)
                .textInputAutocapitalization(.sentences)
                .focused(isFocused)
                .submitLabel(.send)
                .onSubmit(submit)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .fill(Theme.Colors.fieldBackground)
                )
                .accessibilityLabel("Add a food line in plain English")

            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSubmit ? Theme.Colors.tint : Theme.Colors.labelTertiary)
            }
            .disabled(!canSubmit)
            .accessibilityLabel("Log this line")
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        onSubmit()
    }
}

#if DEBUG
#Preview("Composer") {
    @Previewable @State var text = ""
    @Previewable @FocusState var focused: Bool
    return VStack {
        Spacer()
        FoodComposer(
            text: $text,
            isFocused: $focused,
            shortcuts: [FoodShortcut(nickname: "Regular Chipotle order",
                                     items: [LoggedFoodItem(name: "Bowl", calories: 980)],
                                     useCount: 9, createdAt: "", updatedAt: "")],
            recents: [],
            onSubmit: {}, onLogShortcut: { _ in }, onLogRecent: { _ in }, onScanBarcode: {}
        )
        .onAppear { focused = true }
    }
    .background(Theme.Colors.background)
}
#endif
