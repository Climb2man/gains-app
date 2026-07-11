import SwiftUI

struct DateStrip: View {
    /// The currently-selected day, as a local YYYY-MM-DD key.
    let selectedDate: String
    let onSelectDate: (String) -> Void
    /// The ordered list of day keys to render.
    let days: [String]
    /// true shows the small per-day dot (logged data or goal hit that day).
    var adherenceByDay: [String: Bool] = [:]
    /// When true, the strip sits on the hero gradient: unselected days and the dot render white,
    /// and the selected day keeps its floating white box.
    var heroChrome: Bool = false

    private let cellWidth: CGFloat = 52
    private let boxWidth: CGFloat = 48

    private var todayKey: String { DateStrip.toKey(Date()) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Spacing.xs) {
                    ForEach(days, id: \.self) { key in
                        DayCell(
                            dayKey: key,
                            selected: key == selectedDate,
                            isToday: key == todayKey,
                            hasData: adherenceByDay[key] == true,
                            heroChrome: heroChrome,
                            cellWidth: cellWidth,
                            boxWidth: boxWidth,
                            onPress: { onSelectDate(key) }
                        )
                        .id(key)
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)
                .frame(height: 76)
            }
            .onAppear {
                let target = days.contains(selectedDate) ? selectedDate : (days.last ?? selectedDate)
                proxy.scrollTo(target, anchor: .center)
                DispatchQueue.main.async { proxy.scrollTo(target, anchor: .center) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    proxy.scrollTo(target, anchor: .center)
                }
            }
            .accessibilityIdentifier("dateStrip")
        }
    }

    private struct DayCell: View {
        let dayKey: String
        let selected: Bool
        let isToday: Bool
        let hasData: Bool
        var heroChrome: Bool = false
        let cellWidth: CGFloat
        let boxWidth: CGFloat
        let onPress: () -> Void

        private var parsed: (weekday: Int, dateNum: Int) { DateStrip.parseKey(dayKey) }

        private var weekdayColor: Color {
            if selected { return Theme.Colors.label }
            return heroChrome ? Theme.Colors.onTint.opacity(0.8) : Theme.Colors.labelTertiary
        }
        private var dateColor: Color {
            if selected { return Theme.Colors.label }
            if heroChrome { return Theme.Colors.onTint.opacity(isToday ? 1 : 0.9) }
            return isToday ? Theme.Colors.label : Theme.Colors.labelSecondary
        }
        private var markerColor: Color {
            let on = heroChrome ? Theme.Colors.onTint : Theme.Colors.tint
            if hasData { return on }
            if isToday && !selected { return on }
            return .clear
        }

        var body: some View {
            Button(action: onPress) {
                VStack(spacing: Theme.Spacing.xs) {
                    Text(DateStrip.weekdayAbbr[parsed.weekday])
                        .font(Theme.Font.footnote.weight(selected ? .bold : .semibold))
                        .foregroundStyle(weekdayColor)

                    Text("\(parsed.dateNum)")
                        .font(Theme.Font.bodyEmphasized.weight(selected || isToday ? .bold : .medium))
                        .foregroundStyle(dateColor)

                    Circle()
                        .fill(markerColor)
                        .frame(width: 5, height: 5)
                }
                .frame(width: boxWidth)
                .padding(.vertical, Theme.Spacing.sm)
                .background(selectedBackground)
                .frame(width: cellWidth)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selected)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }

        @ViewBuilder
        private var selectedBackground: some View {
            if selected {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(Theme.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 6)
            }
        }

        private var accessibilityText: String {
            var label = DateStrip.spokenDate(dayKey)
            if isToday { label += ", today" }
            if hasData { label += ", has data" }
            return label
        }
    }

    /// 3-letter weekday abbreviations, indexed 0 = Sun … 6 = Sat.
    static let weekdayAbbr = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

    /// Format a Date as a local YYYY-MM-DD key (avoids UTC shifting the day).
    static func toKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Parse a YYYY-MM-DD key into (weekday 0–6, date number) without timezone drift.
    static func parseKey(_ key: String) -> (weekday: Int, dateNum: Int) {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return (0, 1) }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        let calendar = Calendar.current
        guard let date = calendar.date(from: components) else { return (0, parts[2]) }
        let weekday = calendar.component(.weekday, from: date) - 1
        return (weekday, parts[2])
    }

    /// Spoken-date style, built once (the strip can host up to 365 cells).
    private static let spokenDateStyle = Date.FormatStyle().weekday(.wide).month(.wide).day()

    /// Human-readable form of a YYYY-MM-DD key ("Monday, June 9") for VoiceOver. Falls back to the
    /// raw key if it can't be parsed.
    static func spokenDate(_ key: String) -> String {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return key }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        guard let date = Calendar.current.date(from: components) else { return key }
        return date.formatted(spokenDateStyle)
    }

    /// The 7 day keys (Sun→Sat) of the week containing `date`, oldest first.
    static func currentWeekKeys(containing date: Date = Date()) -> [String] {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date) - 1
        guard let sunday = calendar.date(byAdding: .day, value: -weekday, to: calendar.startOfDay(for: date)) else {
            return [toKey(date)]
        }
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: sunday).map { toKey($0) }
        }
    }

    /// Memo backing `trailingYear`, keyed by the day it was built for. MainActor-isolated because only
    /// view bodies read it.
    @MainActor private static var trailingYearMemo: (day: String, keys: [String])?

    /// Trailing-year key list. Both strips read this instead of rebuilding 365 keys in `body` every
    /// render, which also lets LazyHStack diff a stable array.
    ///
    /// Memoized per CALENDAR DAY, not per process. As a `static let` it was built once at launch, so an
    /// app suspended overnight came back with a strip whose last cell was yesterday and no cell for
    /// today at all, leaving the user no way to tap back to the current day.
    @MainActor
    static var trailingYear: [String] {
        let today = toKey(Date())
        if let memo = trailingYearMemo, memo.day == today { return memo.keys }
        let keys = trailingKeys(days: 365)
        trailingYearMemo = (day: today, keys: keys)
        return keys
    }

    /// A trailing range of day keys ending today (oldest first), e.g. the past year, so the strip
    /// scrolls back across months. Rendered in a LazyHStack; opens scrolled to today (the last cell).
    static func trailingKeys(days: Int) -> [String] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<max(1, days)).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { toKey($0) }
        }
    }
}
