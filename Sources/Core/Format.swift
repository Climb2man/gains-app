import Foundation

enum Format {
    private static let lbPerKg = 2.2046226218
    private static let cmPerInch = 2.54
    private static let inchesPerFoot = 12

    private static let intFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.locale = Locale(identifier: "en_US")
        return f
    }()

    /// Round to the nearest integer and group thousands, e.g. 1850 -> "1,850".
    static func int(_ n: Double) -> String {
        intFormatter.string(from: NSNumber(value: n.rounded())) ?? String(Int(n.rounded()))
    }

    /// One-decimal display, dropping a trailing ".0", e.g. 72.0 -> "72", 71.6 -> "71.6".
    static func oneDecimal(_ n: Double) -> String {
        let rounded = (n * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }

    /// Convert kilograms → pounds (boundary conversion; storage stays metric).
    static func kgToLb(_ kg: Double) -> Double {
        kg * lbPerKg
    }

    /// A "172.4 lb" display string from a stored kg value (one decimal, kg never shown).
    static func weightLb(_ kg: Double) -> String {
        "\(oneDecimal(kgToLb(kg))) lb"
    }

    /// A compact `5'10"` height label from centimeters (never renders cm).
    static func feetInches(_ cm: Double) -> String {
        let totalInches = Int((cm / cmPerInch).rounded())
        let feet = totalInches / inchesPerFoot
        let inches = totalInches % inchesPerFoot
        return "\(feet)'\(inches)\""
    }

    /// A signed, formatted delta magnitude + its direction for a delta badge.
    static func deltaBadge(_ delta: Double, format: (Double) -> String) -> (value: String, direction: DeltaDirection) {
        if delta == 0 { return (format(0), .flat) }
        let sign = delta > 0 ? "+" : "−"
        return ("\(sign)\(format(abs(delta)))", delta > 0 ? .up : .down)
    }

    private static let weekdayShort = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    /// A short "Mon 3" label for a local YYYY-MM-DD key (used in day-scoped card headers).
    static func shortDayLabel(_ dayKey: String) -> String {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return dayKey }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        let calendar = Calendar.current
        guard let date = calendar.date(from: components) else { return dayKey }
        let weekday = calendar.component(.weekday, from: date) - 1
        return "\(weekdayShort[weekday]) \(parts[2])"
    }

    /// A "8:12 AM" local time-of-day from an ISO timestamp (for ledger row subtitles).
    private static let isoTimeParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoTimeParserPlain = ISO8601DateFormatter()
    private static let timeOfDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "h:mm a"
        return f
    }()

    static func timeLabel(_ iso: String) -> String {
        let date = isoTimeParser.date(from: iso) ?? isoTimeParserPlain.date(from: iso)
        guard let date else { return "" }
        return timeOfDayFormatter.string(from: date)
    }
}

enum DeltaDirection {
    case up, down, flat
}
