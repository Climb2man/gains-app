import Foundation

enum GainsSliceBuilder {
    /// How far back each domain reaches. Bounded so a single push stays small and the Whoop
    /// per-day fetches stay cheap (each is cache-first).
    private static let nutritionDays = 30
    private static let journalDays = 7
    private static let workoutDays = 14
    private static let whoopDays = 7

    /// Build the slice as a JSONSerialization-safe dictionary. Async because the Whoop summary is.
    @MainActor
    static func build(appModel: AppModel) async -> [String: Any] {
        var slice: [String: Any] = [
            "as_of": FoodLogStore.isoNow(),
            "timezone": TimeZone.current.identifier,
            "nutrition": ["days": nutritionDaysJSON(appModel)],
            "workouts": ["days": workoutDaysJSON(appModel)],
            "whoop": ["days": await whoopDaysJSON(appModel)],
            "weight": ["points": weightPointsJSON(appModel)],
        ]
        if let profile = profileJSON(appModel) { slice["profile"] = profile }
        slice["streaks"] = streaksJSON(appModel)
        return slice
    }

    @MainActor
    private static func weightPointsJSON(_ appModel: AppModel) -> [[String: Any]] {
        appModel.weightStore.entries.map { entry -> [String: Any] in
            var p: [String: Any] = ["date": entry.date, "lb": round1(Units.kgToLb(entry.kg))]
            if let bf = entry.bodyFatPct { p["body_fat_pct"] = round1(bf) }
            return p
        }
    }

    @MainActor
    private static func profileJSON(_ appModel: AppModel) -> [String: Any]? {
        guard let profile = appModel.profile else { return nil }
        let goals = appModel.nutritionStore.goals
        let ftIn = Units.cmToFtIn(profile.heightCm)
        var out: [String: Any] = [
            "sex": profile.sex.rawValue,
            "age_years": profile.ageYears,
            "height": "\(ftIn.feet)'\(ftIn.inches)\"",
            "weight_lb": round1(Units.kgToLb(profile.weightKg)),
            "goals": [
                "calories": goals.calorieGoal,
                "protein_g": goals.proteinGoal,
                "carb_g": goals.carbGoal,
                "fat_g": goals.fatGoal,
                "steps": goals.stepsGoal,
            ],
        ]
        if let name = profile.name, !name.isEmpty { out["name"] = name }
        return out
    }

    @MainActor
    private static func streaksJSON(_ appModel: AppModel) -> [String: Any] {
        let nutrition = appModel.nutritionStore
        let rate = nutrition.hitRate(7)
        return [
            "current_days": nutrition.currentStreak,
            "longest_days": nutrition.longestStreak,
            "last7": ["hits": rate.hits, "total": rate.total],
        ]
    }

    @MainActor
    private static func nutritionDaysJSON(_ appModel: AppModel) -> [[String: Any]] {
        let journalKeys = Set(recentDayKeys(journalDays))
        return recentDayKeys(nutritionDays).compactMap { key in
            guard appModel.foodLog.hasEntries(on: key) else { return nil }
            let totals = appModel.foodLog.totals(on: key)
            var day: [String: Any] = [
                "date": key,
                "calories": round1(totals.calories),
                "protein_g": round1(totals.proteinG),
                "carb_g": round1(totals.carbsG),
                "fat_g": round1(totals.fatG),
                "sugar_g": round1(totals.sugarG),
                "fiber_g": round1(totals.fiberG),
                "sodium_mg": round1(totals.sodiumMg),
            ]
            day["water_ml"] = round1(totals.waterMilliliters)
            if journalKeys.contains(key) {
                day["journal"] = appModel.foodLog.entries(on: key).map(journalLineJSON)
            }
            return day
        }
    }

    private static func journalLineJSON(_ entry: FoodJournalEntry) -> [String: Any] {
        var line: [String: Any] = [
            "text": entry.foodText,
            "logged_at": entry.loggedAt,
            "status": entry.status.rawValue,
            "items": entry.items.map { item -> [String: Any] in
                var out: [String: Any] = [
                    "name": item.name,
                    "calories": round1(item.calories),
                    "protein_g": round1(item.proteinG),
                    "carb_g": round1(item.carbsG),
                    "fat_g": round1(item.fatG),
                ]
                if item.isWaterEntry { out["is_water"] = true }
                if let a = item.assumptions, !a.isEmpty { out["assumptions"] = a }
                if let c = item.confidenceScore { out["confidence"] = c }
                return out
            },
        ]
        return line
    }

    @MainActor
    private static func workoutDaysJSON(_ appModel: AppModel) -> [[String: Any]] {
        recentDayKeys(workoutDays).compactMap { key in
            let sessions = appModel.workoutLog.entries(on: key)
            guard !sessions.isEmpty else { return nil }
            return [
                "date": key,
                "sessions": sessions.map { entry -> [String: Any] in
                    var s: [String: Any] = [
                        "logged_at": entry.date,
                        "raw": entry.rawText,
                        "exercises": entry.exercises.map(WorkoutLogFormat.exerciseSummary),
                    ]
                    if let title = entry.title, !title.isEmpty { s["title"] = title }
                    return s
                },
            ]
        }
    }

    @MainActor
    private static func whoopDaysJSON(_ appModel: AppModel) async -> [[String: Any]] {
        guard appModel.whoopLinked else { return [] }
        let today = FoodLogStore.dayKey(Date())
        var days: [[String: Any]] = []
        for key in recentDayKeys(whoopDays) {
            guard let s = await appModel.whoop.summary(date: key == today ? nil : key, force: false)
            else { continue }
            var day: [String: Any] = ["date": key]
            if let v = s.recoveryPct { day["recovery_pct"] = round1(v) }
            if let v = s.hrvMs { day["hrv_ms"] = round1(v) }
            if let v = s.rhrBpm { day["resting_hr_bpm"] = round1(v) }
            if let v = s.sleepHours { day["sleep_hours"] = round1(v) }
            if let v = s.sleepPerformancePct { day["sleep_performance_pct"] = round1(v) }
            if let v = s.dayStrain { day["day_strain"] = round1(v) }
            if let v = s.calories { day["calories_burned"] = round1(v) }
            if let v = s.steps?.count { day["steps"] = v }
            if day.count > 1 { days.append(day) }
        }
        return days
    }

    /// The last `n` local day keys (YYYY-MM-DD), newest first.
    private static func recentDayKeys(_ n: Int) -> [String] {
        let cal = Calendar.current
        let now = Date()
        return (0 ..< n).compactMap { offset in
            cal.date(byAdding: .day, value: -offset, to: now).map(FoodLogStore.dayKey)
        }
    }

    private static func round1(_ value: Double) -> Double { (value * 10).rounded() / 10 }
}
