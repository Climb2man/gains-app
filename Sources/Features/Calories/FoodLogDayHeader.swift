import SwiftUI

struct FoodLogDayHeader: View {
    let title: String
    let isToday: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onToday: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.Colors.labelSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Previous day")

            VStack(spacing: 0) {
                Txt(title, variant: .title2)
                if !isToday {
                    Button(action: onToday) {
                        Txt("Jump to today", variant: .footnote, color: .tint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Jump to today")
                }
            }
            .frame(maxWidth: .infinity)

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isToday ? Theme.Colors.labelTertiary : Theme.Colors.labelSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(isToday)
            .accessibilityLabel("Next day")
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }
}

#if DEBUG
#Preview("Day header") {
    VStack(spacing: Theme.Spacing.xl) {
        FoodLogDayHeader(title: "Today", isToday: true, onPrevious: {}, onNext: {}, onToday: {})
        FoodLogDayHeader(title: "Yesterday", isToday: false, onPrevious: {}, onNext: {}, onToday: {})
    }
    .background(Theme.Colors.background)
}
#endif
