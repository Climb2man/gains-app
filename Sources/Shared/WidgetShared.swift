import SwiftUI

#if canImport(WidgetKit)
import WidgetKit
#endif

/// The minimal slice the widget needs to render today's calories-left ring. `Codable` so it round-trips
/// as JSON through the App Group `UserDefaults`. `date` is the local `YYYY-MM-DD` key the snapshot was
/// written for, so the widget can detect a stale day and show a neutral placeholder instead of
/// yesterday's numbers.
///
/// Only `caloriesConsumed`/`calorieGoal` drive today's calories widget; `recoveryPct`, `steps`, and
/// `stepsGoal` are optional, carried so a future recovery/steps widget needs no second store. They are
/// non-identifying counts, never a classification.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// Local `YYYY-MM-DD` key the totals belong to (so the widget can detect a stale day).
    var date: String
    /// Calories consumed so far today (sum of logged entries). Whole kcal.
    var caloriesConsumed: Int
    /// The user's daily calorie goal: a target they set, not a recommendation. Whole kcal.
    var calorieGoal: Int
    /// Optional: today's recovery % (0–100) for a future recovery widget. nil when unknown.
    var recoveryPct: Int?
    /// Optional: today's step count for a future steps widget. nil when unknown.
    var steps: Int?
    /// Optional: the user's daily step goal. nil when unknown.
    var stepsGoal: Int?

    init(
        date: String,
        caloriesConsumed: Int,
        calorieGoal: Int,
        recoveryPct: Int? = nil,
        steps: Int? = nil,
        stepsGoal: Int? = nil
    ) {
        self.date = date
        self.caloriesConsumed = caloriesConsumed
        self.calorieGoal = calorieGoal
        self.recoveryPct = recoveryPct
        self.steps = steps
        self.stepsGoal = stepsGoal
    }

    /// Calories remaining against the goal (can go negative when over). Derived, not stored.
    var caloriesLeft: Int { calorieGoal - caloriesConsumed }

    /// True once the user has eaten past the goal. Drives the "over" copy + a danger-tinted ring.
    var isOver: Bool { caloriesConsumed > calorieGoal && calorieGoal > 0 }

    /// Fraction of the goal consumed, 0…1 (clamped). The ring's fill length. Guards a zero/garbage goal.
    var progress: Double {
        guard calorieGoal > 0 else { return 0 }
        return min(1, max(0, Double(caloriesConsumed) / Double(calorieGoal)))
    }

    /// Neutral, non-PHI placeholder for the widget gallery and before any data is written.
    /// Numbers are illustrative defaults, never the user's data.
    static let placeholder = WidgetSnapshot(
        date: "", caloriesConsumed: 1240, calorieGoal: 2200
    )
}

/// The user's day-countdown target: the date to count down to plus an optional event label. Set in the
/// app (Health → Day Countdown) via a calendar `DatePicker` and read by the widget through the App Group.
struct CountdownConfig: Codable, Equatable, Sendable {
    var targetDate: Date
    var label: String

    init(targetDate: Date, label: String = "") {
        self.targetDate = targetDate
        self.label = label
    }

    /// The end of the current year: the default target until the user picks a date.
    static func endOfYear(from date: Date = Date()) -> Date {
        let cal = Calendar.current
        let year = cal.component(.year, from: date)
        return cal.date(from: DateComponents(year: year, month: 12, day: 31)) ?? date
    }

    static var `default`: CountdownConfig { CountdownConfig(targetDate: endOfYear(), label: "") }
}

/// Reads/writes the `WidgetSnapshot` as JSON in the shared App Group `UserDefaults`, so the app's write
/// is visible to the widget extension (a separate process). Falls back to `.standard` when the App Group
/// suite is unavailable (e.g. an unsigned simulator build, before the entitlement is granted). The
/// fallback keeps the app's write side working everywhere; cross-process reads only work once the App
/// Group is live.
enum WidgetSharedStore {
    /// The App Group identifier. Must match the `application-groups` entitlement in both the app and the
    /// widget extension entitlements files.
    static let appGroupID = "group.com.nxw.gains"

    /// JSON key the snapshot lives under inside the shared defaults.
    private static let snapshotKey = "gains.widget.snapshot.v1"

    /// The shared defaults, or `.standard` when the App Group suite isn't available yet (see type doc).
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    /// Persist the latest snapshot for the widget to read. No-ops on an encode failure so a write never
    /// fails a meal log; the widget keeps showing its last value.
    static func write(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    /// The last snapshot the app wrote, or `nil` when none exists or it's undecodable. The timeline
    /// provider maps `nil` to its own placeholder.
    static func read() -> WidgetSnapshot? {
        guard let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Local `YYYY-MM-DD` key for a date, matching `WidgetSnapshot.date`, so a surface can tell whether
    /// a stored snapshot belongs to the day being rendered.
    static func todayKey(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static let countdownKey = "gains.widget.countdown.v1"

    /// Persist the day-countdown target the user set in the app, for the widget to read.
    static func writeCountdown(_ config: CountdownConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: countdownKey)
    }

    /// The day-countdown target the user set, or nil when none has been set yet (widget uses its default).
    static func readCountdown() -> CountdownConfig? {
        guard let data = defaults.data(forKey: countdownKey) else { return nil }
        return try? JSONDecoder().decode(CountdownConfig.self, from: data)
    }
}

/// The calories-left ring the widget renders, in three layouts:
///   • `.systemSmall`: a ring with the calories-left number centered, plus "left"/"over" and "of N".
///   • `.systemMedium`: the same ring beside a labeled readout (consumed / goal / left).
///   • `.accessoryCircular`: ring only, no number (the lock-screen / StandBy PHI-safe variant).
///
/// Color, spacing, and type come from `Theme`. The ring is built inline (a trimmed `Circle` + angular
/// gradient) with no dependency on the app's `RingChart`, so it compiles inside the extension. It uses
/// `Theme.Chart.calories`, flipping to `Theme.Colors.danger` once the user is over the goal.
struct CaloriesWidgetView: View {
    let snapshot: WidgetSnapshot
    /// Which widget family is being rendered. Defaults to `.systemSmall` so a bare
    /// `CaloriesWidgetView(snapshot:)` (e.g. a SwiftUI #Preview) renders the home-screen look.
    var family: WidgetFamilyKind = .systemSmall

    /// No goal recorded means a fresh install with nothing logged, so render the empty state instead
    /// of zero-math numbers.
    private var isUnconfigured: Bool { snapshot.calorieGoal <= 0 }

    var body: some View {
        Group {
            switch family {
            case .systemSmall, .systemMedium:
                if isUnconfigured { emptyState } else if family == .systemMedium { mediumBody } else { smallBody }
            case .accessoryCircular, .accessoryRectangular, .accessoryInline:
                lockScreenBody
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Fresh-install state: an empty ring plus a nudge to log. Never shows illustrative numbers as the
    /// user's own. The gallery placeholder is the only fake-number surface.
    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ring(size: 96, strokeWidth: 11) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.Colors.labelTertiary)
            }
            Text("Log a meal in Gains")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Colors.labelSecondary)
        }
    }

    /// One coherent VoiceOver sentence per family. Home-screen families speak the full numbers;
    /// `.accessoryCircular` speaks only the percent, mirroring its no-raw-number PHI caveat for spoken
    /// output. All strings restate the user's own logged numbers, never advice or a classification.
    private var accessibilityLabel: String {
        guard !isUnconfigured else { return "Calories: nothing logged yet. Log a meal in Gains." }
        switch family {
        case .systemSmall, .systemMedium:
            return "Calories: \(snapshot.caloriesConsumed) eaten of \(snapshot.calorieGoal) goal, \(abs(snapshot.caloriesLeft)) \(headlineWord)"
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            return "Calories, \(Int(snapshot.progress * 100)) percent of goal"
        }
    }

    /// The metric hue: calories orange normally, danger red once over the goal.
    private var ringColor: Color {
        snapshot.isOver ? Theme.Colors.danger : Theme.Chart.calories
    }

    /// Center headline: calories left, or the over-amount. Whole number, no unit.
    private var headlineNumber: String {
        snapshot.isOver ? "\(snapshot.caloriesConsumed - snapshot.calorieGoal)" : "\(snapshot.caloriesLeft)"
    }

    /// The tiny word beneath the headline number: "left" while under goal, "over" once exceeded.
    private var headlineWord: String { snapshot.isOver ? "over" : "left" }

    private var smallBody: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ring(size: 96, strokeWidth: 11) {
                VStack(spacing: 0) {
                    Text(headlineNumber)
                        .font(Theme.Font.number(size: 26, weight: .bold))
                        .foregroundStyle(Theme.Colors.label)
                    Text(headlineWord)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.Colors.labelSecondary)
                }
            }
            Text("of \(snapshot.calorieGoal) cal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Colors.labelTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.md)
    }

    private var mediumBody: some View {
        HStack(spacing: Theme.Spacing.lg) {
            ring(size: 104, strokeWidth: 12) {
                VStack(spacing: 0) {
                    Text(headlineNumber)
                        .font(Theme.Font.number(size: 28, weight: .bold))
                        .foregroundStyle(Theme.Colors.label)
                    Text(headlineWord)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Colors.labelSecondary)
                }
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Label("Today's calories", systemImage: "flame.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ringColor)
                    .labelStyle(.titleAndIcon)
                statRow(label: "Eaten", value: "\(snapshot.caloriesConsumed)")
                statRow(label: "Goal", value: "\(snapshot.calorieGoal)")
                statRow(label: snapshot.isOver ? "Over" : "Left",
                        value: snapshot.isOver
                            ? "\(snapshot.caloriesConsumed - snapshot.calorieGoal)"
                            : "\(snapshot.caloriesLeft)")
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(Theme.Spacing.lg)
    }

    /// One "Label  value" line in the medium widget's readout column.
    private func statRow(label: String, value: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.labelSecondary)
            Spacer(minLength: Theme.Spacing.sm)
            Text(value)
                .font(Theme.Font.number(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Colors.label)
        }
        .frame(maxWidth: 130, alignment: .leading)
    }

    private var lockScreenBody: some View {
        ZStack {
            Circle()
                .stroke(ringColor.opacity(0.22), lineWidth: 6)
            Circle()
                .trim(from: 0, to: snapshot.progress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "flame.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ringColor)
        }
        .padding(2)
    }

    /// A trimmed-circle progress ring with an angular gradient sweep, matching the app's ring look but
    /// self-contained for the extension. `center` is overlaid in the middle.
    private func ring<Center: View>(
        size: CGFloat,
        strokeWidth: CGFloat,
        @ViewBuilder center: () -> Center
    ) -> some View {
        ZStack {
            Circle()
                .stroke(ringColor.opacity(0.14), style: StrokeStyle(lineWidth: strokeWidth))
            Circle()
                .trim(from: 0, to: snapshot.progress)
                .stroke(
                    AngularGradient(
                        colors: [Theme.Chart.light(ringColor), ringColor],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            center()
        }
        .frame(width: size, height: size)
    }
}

/// A glanceable "X days left" countdown to a date the user picks in the app (Health → Day Countdown),
/// with an optional event label. Pure calendar math, no health numbers, so it's safe anywhere including
/// the lock screen. `daysLeft` is precomputed by the provider (it only changes at local midnight); the
/// view just renders it.
struct DayCountdownView: View {
    /// Whole days from today (local midnight) to the target. >0 future, 0 today, <0 past.
    let daysLeft: Int
    /// The user's event label (e.g. "Trip"). Empty → the formatted target date is shown instead.
    var label: String = ""
    /// The target date, for the secondary date line + the no-label fallback. Nil only in previews.
    var targetDate: Date? = nil
    var family: WidgetFamilyKind = .systemSmall

    private var tint: Color { Theme.Chart.sleep }

    /// The headline: the day count, or "Today" when the target is today.
    private var number: String { daysLeft == 0 ? "Today" : "\(abs(daysLeft))" }

    /// The caption under the number ("days left" / "day left" / "days ago"). Empty on the day itself.
    private var caption: String {
        switch daysLeft {
        case 0: return ""
        case 1: return "day left"
        case -1: return "day ago"
        case let d where d > 1: return "days left"
        default: return "days ago"
        }
    }

    /// The top label: the user's event (uppercased), else the formatted target date, else a default.
    private var topLabel: String {
        if !label.trimmingCharacters(in: .whitespaces).isEmpty { return label.uppercased() }
        if let targetDate { return targetDate.formatted(.dateTime.month(.abbreviated).day()).uppercased() }
        return "COUNTDOWN"
    }

    var body: some View {
        Group {
            switch family {
            case .systemSmall: smallBody
            case .systemMedium: mediumBody
            case .accessoryCircular: lockScreenBody
            case .accessoryRectangular: rectangularBody
            case .accessoryInline: inlineBody
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.isEmpty ? "\(abs(daysLeft)) \(caption)" : "\(label): \(abs(daysLeft)) \(caption)")
    }

    /// The single inline string (the `.accessoryInline` line above the lock-screen clock).
    private var inlineText: String {
        let core = daysLeft == 0 ? "Today" : "\(abs(daysLeft)) \(caption)"
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? core : "\(trimmed) · \(core)"
    }

    private func header(size: CGFloat) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "calendar")
                .font(.system(size: size - 1, weight: .bold))
                .foregroundStyle(tint)
            Text(topLabel)
                .font(.system(size: size, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(Theme.Colors.labelSecondary)
                .lineLimit(1)
        }
    }

    private func bigNumber(size: CGFloat) -> some View {
        Text(number)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Theme.Colors.label)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
    }

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            header(size: 11)
            Spacer(minLength: 0)
            bigNumber(size: daysLeft == 0 ? 40 : 58)
            if !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(Theme.Spacing.lg)
    }

    private var mediumBody: some View {
        HStack(spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                header(size: 13)
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    bigNumber(size: daysLeft == 0 ? 44 : 60)
                    if !caption.isEmpty {
                        Text(caption)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                }
                if let targetDate {
                    Text(targetDate.formatted(date: .complete, time: .omitted))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Colors.labelTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(Theme.Spacing.lg)
    }

    /// Lock-screen circular complication: the day count + a tiny "days". Tinted monochrome by the system.
    private var lockScreenBody: some View {
        VStack(spacing: -2) {
            Text(number)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            if daysLeft != 0 {
                Text("days")
                    .font(.system(size: 9, weight: .semibold))
            }
        }
        .padding(2)
    }

    /// Lock-screen rectangular: the label, the "N days left" headline, and (room permitting) the date.
    /// No hard-coded colors: the lock screen renders accessory widgets in the system's tint.
    private var rectangularBody: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.system(size: 20, weight: .semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text(topLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(number)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    if !caption.isEmpty {
                        Text(caption).font(.system(size: 12, weight: .medium))
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// Lock-screen inline (the single line beside the clock): "Label · N days left", with a calendar glyph.
    private var inlineBody: some View {
        Label(inlineText, systemImage: "calendar")
    }
}

/// A tiny mirror of the WidgetKit families this widget supports, so `CaloriesWidgetView` need not
/// import WidgetKit. It's rendered by the extension and by the in-app `-showWidgetPreview` hook, which
/// has no WidgetKit family value. The extension maps `WidgetFamily` to `WidgetFamilyKind`.
enum WidgetFamilyKind: CaseIterable {
    case systemSmall
    case systemMedium
    case accessoryCircular
    case accessoryRectangular
    case accessoryInline
}

#if canImport(WidgetKit)
extension WidgetFamilyKind {
    /// Map a live `WidgetFamily` (from the extension's `@Environment(\.widgetFamily)`) to our kind,
    /// folding any unsupported family onto `.systemSmall` as a safe default.
    init(_ family: WidgetFamily) {
        switch family {
        case .systemMedium: self = .systemMedium
        case .accessoryCircular: self = .accessoryCircular
        case .accessoryRectangular: self = .accessoryRectangular
        case .accessoryInline: self = .accessoryInline
        default: self = .systemSmall
        }
    }
}
#endif
