import SwiftUI

/// A single quiet line: "24 days to Trip".
///
/// The countdown was originally a lock-screen widget. Widgets need App Groups, which Apple does not
/// grant free personal teams, so the widget was removed — leaving the Health → Day Countdown setting
/// writing a date that nothing displayed. This puts the reading back in front of the user, in the app.
///
/// Deliberately not a Card. It is a reference point, not a metric: it earns one line above the day's
/// real content and nothing more. It renders nothing until a countdown is set, and nothing again once
/// the date has passed, so it never occupies space it has not earned.
struct DayCountdownStrip: View {
    /// Read on every render rather than cached in `@State`.
    ///
    /// The value is edited on a different screen (Health → Day Countdown). Holding it in state and
    /// loading it in `onAppear` meant that setting a date and returning here could show the old value
    /// — or nothing — until the app was relaunched, because a tab that stays mounted does not
    /// necessarily re-fire `onAppear`. Reading `UserDefaults` is cheap enough to do every time.
    private var config: CountdownConfig? { WidgetSharedStore.readCountdown() }

    /// nil when no countdown is set, or when the target has already passed.
    private var daysLeft: Int? {
        guard let days = config?.daysRemaining(), days >= 0 else { return nil }
        return days
    }

    var body: some View {
        Group {
            if let days = daysLeft, let config {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Colors.labelTertiary)

                    Text(days == 0 ? "Today" : "\(days)")
                        .font(Theme.Font.footnote.weight(.bold))
                        .foregroundStyle(Theme.Colors.label)
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    Text(Self.suffix(days: days, label: config.label))
                        .font(Theme.Font.footnote)
                        .foregroundStyle(Theme.Colors.labelTertiary)

                    Spacer(minLength: 0)
                }
                .accessibilityElement()
                .accessibilityLabel(Self.accessibilityText(days: days, label: config.label))
            }
        }
    }

    /// "days to Trip" / "days left" / "is the day" — the label is optional, so the sentence has to
    /// read properly without one. Static so it can be tested without building a view.
    static func suffix(days: Int, label: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if days == 0 { return trimmed.isEmpty ? "is the day" : "" }
        let unit = days == 1 ? "day" : "days"
        return trimmed.isEmpty ? "\(unit) left" : "\(unit) to \(trimmed)"
    }

    static func accessibilityText(days: Int, label: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if days == 0 { return trimmed.isEmpty ? "Today is the day" : "Today is \(trimmed)" }
        let unit = days == 1 ? "day" : "days"
        return "\(days) \(unit) to \(trimmed.isEmpty ? "your target date" : trimmed)"
    }
}
