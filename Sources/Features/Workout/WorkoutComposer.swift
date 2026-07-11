import SwiftUI

struct WorkoutComposer: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let shortcuts: [WorkoutShortcut]
    let onSubmit: () -> Void
    let onLogShortcut: (WorkoutShortcut) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if isFocused.wrappedValue {
                WorkoutQuickAddChips(shortcuts: shortcuts, onLogShortcut: onLogShortcut)
                if !shortcuts.isEmpty { HairlineDivider() }
            }
            inputBar
        }
        .background(Theme.Colors.surface)
        .overlay(alignment: .top) { HairlineDivider() }
    }

    private var inputBar: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 22))
                .foregroundStyle(Theme.Colors.tint)

            TextField("Log a workout: “Bench 3x10 @135, incline DB 10,10,8 @50”…",
                      text: $text, axis: .vertical)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Colors.label)
                .lineLimit(1...5)
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
                .accessibilityLabel("Log a workout in plain English")

            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSubmit ? Theme.Colors.tint : Theme.Colors.labelTertiary)
            }
            .disabled(!canSubmit)
            .accessibilityLabel("Log this workout")
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

/// A horizontally-scrolling row of saved workout tiles, most-used first, for zero-AI re-logging.
/// Each tile shows a dumbbell glyph, the nickname and exercise count, and a circular "+" add button.
struct WorkoutQuickAddChips: View {
    let shortcuts: [WorkoutShortcut]
    let onLogShortcut: (WorkoutShortcut) -> Void

    var body: some View {
        if shortcuts.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal) {
                LazyHStack(spacing: Theme.Spacing.sm) {
                    ForEach(shortcuts) { shortcut in
                        WorkoutQuickChip(shortcut: shortcut, log: { onLogShortcut(shortcut) })
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
            }
            .scrollIndicators(.hidden)
            .background(Theme.Colors.surface)
            .accessibilityLabel("Quick add saved workouts")
        }
    }
}

/// A single quick-add workout tile.
private struct WorkoutQuickChip: View {
    let shortcut: WorkoutShortcut
    let log: () -> Void
    @State private var logged = false

    var body: some View {
        Button {
            logged.toggle()
            log()
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Colors.tint)
                    .frame(width: 34, height: 34)
                    .background(Theme.Colors.tintSoft, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Txt(shortcut.nickname, variant: .subhead).lineLimit(1)
                    Txt(WorkoutLogFormat.shortcutSummary(shortcut), variant: .footnote, color: .labelTertiary)
                }
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.Colors.onTint)
                    .symbolEffect(.bounce, value: logged)
                    .frame(width: 28, height: 28)
                    .background(Theme.Colors.tint, in: .circle)
            }
            .padding(.vertical, Theme.Spacing.sm)
            .padding(.horizontal, Theme.Spacing.sm)
            .frame(maxWidth: 220)
            .background(tileShape.fill(Theme.Colors.surface))
            .overlay { tileShape.stroke(Color.black.opacity(0.06), lineWidth: 1) }
            .cardShadow(Theme.Shadow.card)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Log saved workout \(shortcut.nickname), \(WorkoutLogFormat.shortcutSummary(shortcut))")
    }

    private var tileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
    }
}

#if DEBUG
#Preview("Workout composer") {
    @Previewable @State var text = ""
    @Previewable @FocusState var focused: Bool
    return VStack {
        Spacer()
        WorkoutComposer(
            text: $text,
            isFocused: $focused,
            shortcuts: [
                WorkoutShortcut(nickname: "Push day",
                                exercises: [WorkoutExercise(name: "Bench Press")],
                                useCount: 9, createdAt: "", updatedAt: ""),
            ],
            onSubmit: {}, onLogShortcut: { _ in }
        )
        .onAppear { focused = true }
    }
    .background(Theme.Colors.background)
}
#endif
