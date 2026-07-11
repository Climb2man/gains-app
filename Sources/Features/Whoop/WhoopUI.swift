import SwiftUI

/// Toolbar refresh button: a glass chrome circle that spins while a refresh is in flight (instant
/// under Reduce Motion). Glass stays on the chrome layer, never on a data card.
struct WhoopToolbarRefreshButton: View {
    let busy: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(busy ? Theme.Colors.labelTertiary : Theme.Colors.tint)
                .frame(width: 36, height: 36)
                .gainsGlassChrome(in: Circle())
                .rotationEffect(.degrees(busy && !reduceMotion ? 360 : 0))
                .animation(
                    busy && !reduceMotion ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default,
                    value: busy
                )
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel("Refresh Whoop data")
    }
}

/// A small section title: a leading SF Symbol in the section's hue + a body-emphasized label.
struct WhoopSectionTitle: View {
    let icon: String
    let title: String
    var color: Color = Theme.Colors.labelSecondary

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
            Txt(title, variant: .bodyEmphasized)
        }
    }
}

/// A label-over-value readout. `accent` tints the value with a per-metric hue. The value uses
/// monospaced digits and counts up via numericText (instant under Reduce Motion).
struct WhoopStat: View {
    let label: String
    let value: String
    var accent: Color?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Txt(label, variant: .footnote, color: .labelSecondary)
            Text(value)
                .font(Theme.Font.statNumber)
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())
                .foregroundStyle(accent ?? Theme.Colors.label)
        }
    }
}

/// Shown when Whoop isn't linked: a "connect me" card with a pulse glyph and optional connect button.
struct ConnectWhoopState: View {
    let title: String
    let message: String
    var onConnectWhoop: (() -> Void)?

    var body: some View {
        Card {
            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.Chart.recovery)
                    .frame(width: 72, height: 72)
                    .background(Theme.Colors.fieldBackground, in: Circle())
                Txt(title, variant: .title2, center: true)
                Txt(message, variant: .subhead, color: .labelSecondary, center: true)
                if let onConnectWhoop {
                    PrimaryButton(title: "Connect Whoop", action: onConnectWhoop)
                        .padding(.top, Theme.Spacing.sm)
                } else {
                    Txt("Add your Whoop login in Settings to get started.",
                        variant: .footnote, color: .labelTertiary, center: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.xl)
        }
    }
}

/// Linked, loading the snapshot: a pulse glyph and message card.
struct WhoopLoadingState: View {
    let message: String

    var body: some View {
        Card {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.Colors.labelTertiary)
                Txt(message, variant: .subhead, color: .labelSecondary, center: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.xl)
        }
    }
}

/// Linked but no usable snapshot for this day: a retry card that doesn't guess the cause.
struct WhoopNoDataState: View {
    let title: String
    let message: String
    var icon: String = "cloud.slash"
    var refreshing: Bool = false
    let onRefresh: () -> Void

    var body: some View {
        Card {
            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.Colors.labelTertiary)
                Txt(title, variant: .subhead, color: .labelSecondary, center: true)
                Txt(message, variant: .footnote, color: .labelTertiary, center: true)
                SecondaryButton(title: refreshing ? "Refreshing…" : "Try again",
                                disabled: refreshing, action: onRefresh)
                    .padding(.top, Theme.Spacing.sm)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.xl)
        }
    }
}

/// A two-column, equal-width row.
struct WhoopRow<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) { content }
    }
}

enum WhoopColor {
    /// Recovery color: green (high) / yellow (moderate) / red (low). Prefer Whoop's own reported state
    /// so it matches the Whoop app; otherwise band the percentage. A visual echo of the number, not a
    /// health verdict.
    static func recovery(_ pct: Double?, state: WhoopRecoveryState?) -> Color {
        switch state {
        case .green: return Theme.Colors.success
        case .yellow: return Theme.Colors.warning
        case .red: return Theme.Colors.danger
        case nil: break
        }
        guard let pct else { return Theme.Colors.labelTertiary }
        if pct >= 67 { return Theme.Colors.success }
        if pct >= 34 { return Theme.Colors.warning }
        return Theme.Colors.danger
    }

    /// Whoop's 0–3 stress scale: ≥ 2 "high" (red), ≥ 1 "medium" (amber), below "low" (green). Prefer
    /// Whoop's own state word so the color matches the app.
    static func stress(_ level: Double?, state: String? = nil) -> Color {
        switch state?.uppercased() {
        case "STRESSED", "HIGH": return Theme.Colors.danger
        case "RELAXED", "LOW", "CALM": return Theme.Colors.success
        case "MEDIUM", "MODERATE": return Theme.Colors.warning
        default: break
        }
        guard let level else { return Theme.Colors.labelTertiary }
        if level >= 2 { return Theme.Colors.danger }
        if level >= 1 { return Theme.Colors.warning }
        return Theme.Colors.success
    }

    /// A plain band word for the current stress level (matches `stress(_:state:)`'s banding).
    static func stressBandLabel(_ level: Double?, state: String? = nil) -> String {
        if state == "CALIBRATING" { return "Calibrating" }
        switch state?.uppercased() {
        case "STRESSED", "HIGH": return "High"
        case "RELAXED", "LOW", "CALM": return "Low"
        case "MEDIUM", "MODERATE": return "Medium"
        default: break
        }
        guard let level else { return "No reading yet" }
        if level >= 2 { return "High" }
        if level >= 1 { return "Medium" }
        return "Low"
    }
}

enum WhoopFormat {
    /// One-decimal display, dropping a trailing ".0" (72.0 → "72", 71.64 → "71.6").
    static func oneDecimal(_ n: Double) -> String { Format.oneDecimal(n) }

    /// Title-case a Whoop state token ("STRESSED" → "Stressed"); "" for an absent/blank token.
    static func titleCaseState(_ state: String?) -> String {
        guard let state, !state.isEmpty else { return "" }
        return state.prefix(1).uppercased() + state.dropFirst().lowercased()
    }

    /// A signed Δ-vs-baseline for a delta badge (e.g. "+5 ms", "−3 bpm", "even"), or nil when either
    /// side is absent. `direction` is the raw sign; callers flip it for "lower-is-better" metrics.
    static func delta(_ current: Double?, _ baseline: Double?, unit: String)
        -> (text: String, direction: DeltaDirection)? {
        guard let current, let baseline else { return nil }
        let diff = ((current - baseline) * 10).rounded() / 10
        if diff == 0 { return ("even", .flat) }
        let sign = diff > 0 ? "+" : "−"
        return ("\(sign)\(oneDecimal(abs(diff))) \(unit)", diff > 0 ? .up : .down)
    }

    /// A "baseline X ms/bpm" caption, or "" when no baseline is present.
    static func baselineCaption(_ baseline: Double?, unit: String) -> String {
        guard let baseline else { return "" }
        return "baseline \(oneDecimal(baseline)) \(unit)"
    }

    /// Fractional hours as "7h 24m" (or "24m" under an hour).
    static func hoursMinutes(_ hours: Double) -> String {
        let total = max(0, Int((hours * 60).rounded()))
        let h = total / 60
        let m = total % 60
        return h == 0 ? "\(m)m" : "\(h)h \(m)m"
    }

    /// Whole minutes as "7h 24m" (or "24m" under an hour).
    static func minutesHm(_ minutes: Int) -> String {
        let total = max(0, minutes)
        let h = total / 60
        let m = total % 60
        return h == 0 ? "\(m)m" : "\(h)h \(m)m"
    }

    /// Milliseconds as "7h 24m" (or "24m" under an hour, "0m" when nil/zero).
    static func ms(_ ms: Double?) -> String {
        guard let ms, ms > 0 else { return "0m" }
        return hoursMinutes(ms / 3_600_000)
    }

    /// Milliseconds as a Whoop-style "h:mm" clock (30,120,000 → "8:22"). "0:00" for nil/zero.
    static func msClock(_ ms: Double?) -> String {
        guard let ms, ms > 0 else { return "0:00" }
        let total = Int((ms / 60_000).rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    /// Same h:mm clock but "–" (not "0:00") when the value is absent, for the optional metric tiles.
    static func msClockOrDash(_ ms: Double?) -> String { ms == nil ? "–" : msClock(ms) }

    /// A whole-number count display, or "–" when absent.
    static func countOrDash(_ n: Double?) -> String {
        guard let n else { return "–" }
        return String(Int(n.rounded()))
    }

    /// A rounded percentage display, or "–" when absent.
    static func pctOrDash(_ n: Double?) -> String {
        guard let n else { return "–" }
        return "\(Int(n.rounded()))%"
    }

    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoParserPlain = ISO8601DateFormatter()
    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "h:mm a"
        return f
    }()

    /// A clock time-of-day "10:42 PM" from an ISO timestamp, or nil when unparseable.
    static func clock(_ iso: String?) -> String? {
        guard let iso, let date = parseISO(iso) else { return nil }
        return clockFormatter.string(from: date)
    }

    /// "as of 6:42 AM" from the day's recorded-at / updated-at anchor; "" when neither is present.
    static func asOfLabel(_ recordedAt: String?, _ updatedAt: String? = nil) -> String {
        guard let clock = clock(recordedAt ?? updatedAt) else { return "" }
        return "as of \(clock)"
    }

    /// A relative "Xm/h/d ago" / "just now" label from an ISO timestamp; "recently" when unparseable.
    static func relative(_ iso: String) -> String {
        guard let date = parseISO(iso) else { return "recently" }
        let diff = Date().timeIntervalSince(date)
        if diff < 0 { return "just now" }
        let minutes = Int(diff / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }

    /// Parse an ISO timestamp, tolerating both fractional-seconds and plain internet-date forms.
    private static func parseISO(_ iso: String) -> Date? {
        isoParser.date(from: iso) ?? isoParserPlain.date(from: iso)
    }
}
