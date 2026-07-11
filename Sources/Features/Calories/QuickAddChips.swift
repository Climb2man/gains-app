import SwiftUI

struct QuickAddChips: View {
    let shortcuts: [FoodShortcut]
    let recents: [RecentMeal]
    let onLogShortcut: (FoodShortcut) -> Void
    let onLogRecent: (RecentMeal) -> Void

    /// The ordered tile list: saved shortcuts (most-used first) then recents, unified into one row so
    /// it reads as a single quick-add strip rather than two lists.
    private var items: [QuickItem] {
        let saved = shortcuts
            .sorted { $0.useCount > $1.useCount }
            .map { shortcut in
                QuickItem(id: "s-\(shortcut.id)", title: shortcut.nickname,
                          calories: shortcut.totalCalories, tone: .saved,
                          log: { onLogShortcut(shortcut) })
            }
        let recent = recents.map { recent in
            QuickItem(id: "r-\(recent.name)", title: recent.name,
                      calories: recent.calories, tone: .recent,
                      log: { onLogRecent(recent) })
        }
        return saved + recent
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal) {
                LazyHStack(spacing: Theme.Spacing.sm) {
                    ForEach(items) { item in
                        QuickChip(item: item)
                            .transition(reduceMotion
                                ? .opacity
                                : .move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.xs)
                .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85),
                           value: items.map(\.id))
            }
            .scrollIndicators(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            .background(Theme.Colors.surface)
            .accessibilityLabel("Quick add saved and recent foods")
        }
    }
}

/// One quick-add entry; the saved/recent distinction is just the leading glyph and tone.
private struct QuickItem: Identifiable {
    let id: String
    let title: String
    let calories: Double
    let tone: QuickChip.Tone
    let log: () -> Void
}

private struct QuickChip: View {
    enum Tone {
        case saved, recent

        /// The leading symbol: bookmark for saved shortcuts, clock for recent meals.
        var icon: String {
            switch self {
            case .saved: "bookmark.fill"
            case .recent: "clock.arrow.circlepath"
            }
        }

        var iconColor: Color {
            switch self {
            case .saved: Theme.Colors.tint
            case .recent: Theme.Colors.labelSecondary
            }
        }

        var iconBackground: Color {
            switch self {
            case .saved: Theme.Colors.tintSoft
            case .recent: Theme.Colors.fieldBackground
            }
        }
    }

    let item: QuickItem
    /// Toggled on tap to fire the "+" bounce confirming the log.
    @State private var logged = false

    var body: some View {
        Button {
            logged.toggle()
            item.log()
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                glyphToken
                VStack(alignment: .leading, spacing: 2) {
                    Txt(item.title, variant: .subhead)
                        .lineLimit(1)
                    Txt("\(Format.int(item.calories)) kcal", variant: .footnote, color: .labelTertiary)
                }
                addAffordance
            }
            .padding(.vertical, Theme.Spacing.sm)
            .padding(.leading, Theme.Spacing.sm)
            .padding(.trailing, Theme.Spacing.sm)
            .frame(maxWidth: 220)
            .background(tileShape.fill(Theme.Colors.surface))
            .overlay { tileShape.stroke(Color.black.opacity(0.06), lineWidth: 1) }
            .cardShadow(Theme.Shadow.card)
            .contentShape(.rect)
        }
        .buttonStyle(QuickChipButtonStyle())
        .accessibilityLabel("Log \(item.title), \(Format.int(item.calories)) kilocalories")
        .accessibilityAddTraits(.isButton)
    }

    private var tileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
    }

    private var glyphToken: some View {
        Image(systemName: item.tone.icon)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(item.tone.iconColor)
            .frame(width: 34, height: 34)
            .background(item.tone.iconBackground, in: .circle)
    }

    private var addAffordance: some View {
        Image(systemName: "plus")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Theme.Colors.onTint)
            .symbolEffect(.bounce, value: logged)
            .frame(width: 28, height: 28)
            .background(Theme.Colors.tint, in: .circle)
    }
}

private struct QuickChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

#if DEBUG
#Preview("Quick add chips") {
    QuickAddChips(
        shortcuts: [
            FoodShortcut(nickname: "Regular Chipotle order",
                         items: [LoggedFoodItem(name: "Chipotle bowl", calories: 980)],
                         useCount: 12, createdAt: "", updatedAt: ""),
            FoodShortcut(nickname: "Morning protein shake",
                         items: [LoggedFoodItem(name: "Shake", calories: 240)],
                         useCount: 8, createdAt: "", updatedAt: ""),
        ],
        recents: [RecentMeal(name: "Greek yogurt + berries", calories: 210, proteinG: 18,
                             carbsG: 24, fatG: 4, useCount: 3, lastUsedAt: "")],
        onLogShortcut: { _ in }, onLogRecent: { _ in }
    )
    .background(Theme.Colors.background)
}
#endif
