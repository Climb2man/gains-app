import SwiftUI

/// A single quiet line: "24 days to Trip".
///
/// The countdown was originally a lock-screen widget. Widgets need App Groups, which Apple does not
/// grant free personal teams, so the widget was removed — leaving the Health → Day Countdown setting
/// writing a date that nothing displayed. This puts the reading back in front of the user, in the app.
///
/// Deliberately not a Card. It is a reference point, not a metric: it earns one line above the day's
/// real content and nothing more. It also renders nothing at all until a countdown has been set, so
/// it costs no space for anyone who does not use it.
struct DayCountdownStrip: View {
    /// Re-read on each appearance rather than held in state: the value is set on another screen, and
    /// a stale copy would show yesterday's number after editing it.
    @State private var config: CountdownConfig?

    /// Whole days from today to the target, floored at 0. Compared date-to-date rather than by
    /// elapsed hours, so "tomorrow" reads as 1 day all day today rather than flipping at midday.
    private var daysLeft: Int? {
        guard let config else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let target = cal.startOfDay(for: config.targetDate)
        guard let days = cal.dateComponents([.day], from: today, to: target).day else { return nil }
        return max(0, days)
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

                    Text(countdownSuffix(days: days, label: config.label))
                        .font(Theme.Font.footnote)
                        .foregroundStyle(Theme.Colors.labelTertiary)

                    Spacer(minLength: 0)
                }
                .accessibilityElement()
                .accessibilityLabel(
                    days == 0
                        ? "Today\(config.label.isEmpty ? "" : " is \(config.label)")"
                        : "\(days) days to \(config.label.isEmpty ? "your target date" : config.label)"
                )
            }
        }
        .onAppear { config = WidgetSharedStore.readCountdown() }
    }

    /// "days to Trip" / "days left" / "" — the label is optional, so the sentence has to work without it.
    private func countdownSuffix(days: Int, label: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if days == 0 { return trimmed.isEmpty ? "is the day" : "" }
        let unit = days == 1 ? "day" : "days"
        return trimmed.isEmpty ? "\(unit) left" : "\(unit) to \(trimmed)"
    }
}
