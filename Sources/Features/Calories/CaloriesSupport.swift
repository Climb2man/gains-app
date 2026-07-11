import SwiftUI

enum CaloriesSupport {
    static let kcalPerProteinG: Double = 4
    static let kcalPerCarbG: Double = 4
    static let kcalPerFatG: Double = 9

    /// Weekday initials for the adherence rows + bar-chart axis, indexed by `Calendar` weekday-1.
    static let weekdayInitials = ["S", "M", "T", "W", "T", "F", "S"]

    /// A date's local `YYYY-MM-DD` key, matching `NutritionStore.dayKey`'s boundary. Duplicated as a
    /// nonisolated helper so this presentational utility needn't touch the @MainActor store.
    static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Parse a YYYY-MM-DD local key into a Date at local midnight (matches `dayKey`'s boundary).
    static func keyToDate(_ key: String) -> Date {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return Date() }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return Calendar.current.date(from: components) ?? Date()
    }

    /// The weekday initial ("S","M",…) for a YYYY-MM-DD key.
    static func weekdayInitial(_ key: String) -> String {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: keyToDate(key)) - 1
        return weekdayInitials[safe: weekday] ?? ""
    }

    /// A friendly title for the selected day: "Today", "Yesterday", or e.g. "Mon, Jun 2".
    static func dayTitle(_ key: String) -> String {
        let todayKey = dayKey(Date())
        if key == todayKey { return "Today" }
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        if key == dayKey(yesterday) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: keyToDate(key))
    }

    /// The local Sun–Sat week containing `key`, as ordered YYYY-MM-DD keys.
    static func weekOf(_ key: String) -> [String] {
        let calendar = Calendar.current
        let base = keyToDate(key)
        let weekdayIndex = calendar.component(.weekday, from: base) - 1
        guard let sunday = calendar.date(byAdding: .day, value: -weekdayIndex, to: base) else {
            return [key]
        }
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: sunday).map { dayKey($0) }
        }
    }

    /// Local time-of-day ("8:12 AM") for a meal row, from its ISO timestamp.
    static func entryTime(_ iso: String) -> String {
        Format.timeLabel(iso)
    }

    /// Provenance suffix for a logged meal's macro line ("" for manual entry).
    static func sourceSuffix(_ source: FoodSource) -> String {
        switch source {
        case .aiEstimated: return " · AI estimate"
        case .saved: return " · Saved"
        case .manual: return ""
        }
    }

    /// Scores today's food on protein density, fiber, and added sugar, each relative to its own
    /// calories. Describes the food, never classifies the person.
    static func foodQualities(_ totals: FoodDayTotals) -> [(label: String, score: Double, descriptor: String)] {
        guard totals.calories > 0 else { return [] }

        let proteinCals = totals.proteinG * kcalPerProteinG
        let proteinShare = proteinCals / totals.calories
        let proteinScore = min(1, proteinShare / 0.35)
        let proteinDescriptor = proteinShare >= 0.25
            ? "High protein for the calories so far today."
            : "A moderate share of these calories is protein."

        let fiberPerK = totals.fiberG / (totals.calories / 1000)
        let fiberScore = min(1, fiberPerK / 14)
        let fiberDescriptor = fiberPerK >= 10
            ? "Fiber-dense for the calories logged today."
            : "Lower in fiber for the calories logged today."

        let sugarCals = totals.sugarG * kcalPerCarbG
        let sugarShare = sugarCals / totals.calories
        let sugarScore = min(1, max(0, 1 - sugarShare / 0.25))
        let sugarDescriptor = sugarShare <= 0.10
            ? "Low in added sugar for the calories logged today."
            : "A noticeable share of these calories is sugar."

        return [
            (label: "Protein density", score: proteinScore, descriptor: proteinDescriptor),
            (label: "Fiber", score: fiberScore, descriptor: fiberDescriptor),
            (label: "Added sugar", score: sugarScore, descriptor: sugarDescriptor),
        ]
    }
}

struct MacroCopy {
    let title: String
    let density: String
    let why: String

    static let protein = MacroCopy(
        title: "Protein",
        density: "4 cal/g",
        why: "Repairs tissue, builds muscle, keeps you full."
    )
    static let fat = MacroCopy(
        title: "Fat",
        density: "9 cal/g",
        why: "Hormone production, nutrient absorption, brain health."
    )
    static let carb = MacroCopy(
        title: "Carbohydrate",
        density: "4 cal/g",
        why: "The body's primary, preferred energy for daily activity and exercise."
    )
}
