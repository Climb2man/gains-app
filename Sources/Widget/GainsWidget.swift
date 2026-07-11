import SwiftUI
import WidgetKit

/// The extension's `@main`, the bundle of widgets this extension vends: the calories widget and the
/// day-countdown widget.
@main
struct GainsWidgetBundle: WidgetBundle {
    var body: some Widget {
        CaloriesWidget()
        DayCountdownWidget()
    }
}

/// One point in the widget's timeline: a `WidgetSnapshot` plus the instant WidgetKit should show it.
struct CaloriesEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// Feeds the widget its data. `placeholder` is the redacted gallery state; `getSnapshot` is a single
/// representative render; `getTimeline` reads the latest app-written snapshot and schedules the next
/// refresh ~15 minutes out (the app also forces an immediate reload on every log/goal change).
///
/// Stale-day guard: the app only rewrites the snapshot on a food/goal mutation, so overnight the stored
/// snapshot still carries yesterday's totals. Each read compares `snapshot.date` to the current local
/// day key and substitutes a fresh-day reset (0 consumed against the same goal) when they differ, plus
/// a midnight timeline entry so the rollover lands on time without a refresh.
struct CaloriesProvider: TimelineProvider {
    /// Local `YYYY-MM-DD` key for a date, matching what the app writes into `WidgetSnapshot.date`
    /// (local calendar, no UTC shifting), so a string compare detects a snapshot from a previous day.
    private static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The snapshot corrected for the day `date` falls on: unchanged while it's still that day's data,
    /// otherwise a fresh-day reset (nothing consumed against the same goal) so the widget never renders
    /// yesterday's totals as "today" after local midnight.
    private static func dayCorrected(_ snapshot: WidgetSnapshot, for date: Date) -> WidgetSnapshot {
        let today = dayKey(date)
        guard snapshot.date != today else { return snapshot }
        return WidgetSnapshot(date: today, caloriesConsumed: 0, calorieGoal: snapshot.calorieGoal)
    }

    /// Fresh-install snapshot (nothing written yet): zeros under today's key, which the view renders as
    /// its no-data state. The illustrative `.placeholder` numbers are for the widget gallery only. A
    /// live surface must never present fake data as the user's own.
    private static func emptySnapshot(for date: Date) -> WidgetSnapshot {
        WidgetSnapshot(date: dayKey(date), caloriesConsumed: 0, calorieGoal: 0)
    }

    /// Gallery / loading placeholder: illustrative numbers only, never the user's data.
    func placeholder(in context: Context) -> CaloriesEntry {
        CaloriesEntry(date: Date(), snapshot: .placeholder)
    }

    /// A single representative entry. Reads the real snapshot when present (day-corrected, so a stale
    /// day never flashes); with nothing stored, the gallery (`context.isPreview`) keeps the illustrative
    /// placeholder while a live render gets the empty state.
    func getSnapshot(in context: Context, completion: @escaping (CaloriesEntry) -> Void) {
        let now = Date()
        let snapshot = WidgetSharedStore.read().map { Self.dayCorrected($0, for: now) }
            ?? (context.isPreview ? .placeholder : Self.emptySnapshot(for: now))
        completion(CaloriesEntry(date: now, snapshot: snapshot))
    }

    /// Render the day-corrected current snapshot now, plus a fresh-day entry at the next local midnight
    /// so the ring resets overnight even if no refresh fires, then ask WidgetKit to refresh in ~15
    /// minutes. `.after` is a floor; the app's `reloadAllTimelines()` on each log/goal change is what
    /// updates the ring the instant the user logs.
    func getTimeline(in context: Context, completion: @escaping (Timeline<CaloriesEntry>) -> Void) {
        let now = Date()
        var entries: [CaloriesEntry]
        if let stored = WidgetSharedStore.read() {
            let current = Self.dayCorrected(stored, for: now)
            entries = [CaloriesEntry(date: now, snapshot: current)]
            if let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) {
                entries.append(CaloriesEntry(date: midnight, snapshot: Self.dayCorrected(current, for: midnight)))
            }
        } else {
            entries = [CaloriesEntry(date: now, snapshot: Self.emptySnapshot(for: now))]
        }
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now.addingTimeInterval(900)
        completion(Timeline(entries: entries, policy: .after(next)))
    }
}

/// The calories-left widget. Supports Home-Screen small and medium (numbers shown, device unlocked) and
/// lock-screen `accessoryCircular` (ring only, see the PHI caveat in `CaloriesWidgetView`).
struct CaloriesWidget: Widget {
    private let kind = "com.nxw.gains.CaloriesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CaloriesProvider()) { entry in
            CaloriesWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Calories Left")
        .description("Today's calories consumed and remaining against your goal.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

/// Bridges the timeline entry and active `widgetFamily` into the shared `CaloriesWidgetView`, applying
/// the widget container background (a plain surface on Home-Screen families; clear on the lock screen so
/// the system tint shows through). `containerBackground` is required on iOS 17+.
struct CaloriesWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CaloriesEntry

    var body: some View {
        CaloriesWidgetView(snapshot: entry.snapshot, family: WidgetFamilyKind(family))
            .containerBackground(for: .widget) {
                if family == .accessoryCircular {
                    Color.clear
                } else {
                    Theme.Colors.background
                }
            }
    }
}

/// One timeline point: the day it represents + the precomputed days-left + the label/date to show.
struct DayCountdownEntry: TimelineEntry {
    let date: Date
    let daysLeft: Int
    let label: String
    let targetDate: Date
}

/// Feeds the day-countdown widget. The target date and label come from the App Group; the user sets them
/// in the app (Health → Day Countdown). `daysLeft` only changes at local midnight, so the timeline
/// schedules one entry per day (today plus the next two weeks of midnights) and reloads at the end, so
/// the number decrements on its own even with the app closed.
struct DayCountdownProvider: TimelineProvider {
    private func config() -> CountdownConfig { WidgetSharedStore.readCountdown() ?? .default }

    /// Whole local days from `date` to `target` (>0 future, 0 today, <0 past).
    private func days(to target: Date, from date: Date) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                  to: cal.startOfDay(for: target)).day ?? 0
    }

    private func makeEntry(at date: Date, _ c: CountdownConfig) -> DayCountdownEntry {
        DayCountdownEntry(date: date, daysLeft: days(to: c.targetDate, from: date),
                          label: c.label, targetDate: c.targetDate)
    }

    func placeholder(in context: Context) -> DayCountdownEntry {
        let now = Date()
        let target = Calendar.current.date(byAdding: .day, value: 24, to: now) ?? now
        return DayCountdownEntry(date: now, daysLeft: 24, label: "Trip", targetDate: target)
    }

    func getSnapshot(in context: Context, completion: @escaping (DayCountdownEntry) -> Void) {
        completion(makeEntry(at: Date(), config()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayCountdownEntry>) -> Void) {
        let now = Date()
        let cal = Calendar.current
        let c = config()
        var entries: [DayCountdownEntry] = [makeEntry(at: now, c)]
        var midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        for _ in 0..<14 {
            entries.append(makeEntry(at: midnight, c))
            midnight = cal.date(byAdding: .day, value: 1, to: midnight) ?? midnight
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

/// The day-countdown widget: "X days left" until the date set in the app (Health → Day Countdown).
/// Lock-screen only: rectangular (label + count + date), circular complication, and the inline line.
struct DayCountdownWidget: Widget {
    private let kind = "com.nxw.gains.DayCountdownWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DayCountdownProvider()) { entry in
            DayCountdownEntryView(entry: entry)
        }
        .configurationDisplayName("Day Countdown")
        .description("Days left until your date. Set the date in Gains → Health → Day Countdown.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

/// Bridges the timeline entry and active `widgetFamily` into the shared `DayCountdownView`, applying the
/// widget container background (surface on Home-Screen families; clear on the lock screen so the system
/// tint shows through).
struct DayCountdownEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DayCountdownEntry

    var body: some View {
        DayCountdownView(daysLeft: entry.daysLeft, label: entry.label, targetDate: entry.targetDate,
                         family: WidgetFamilyKind(family))
            .containerBackground(for: .widget) {
                if family == .accessoryCircular {
                    Color.clear
                } else {
                    Theme.Colors.background
                }
            }
    }
}
