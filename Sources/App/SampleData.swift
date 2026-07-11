import Foundation

/// Namespace of ready-made sample values. Pure static data: no state, no side effects.
enum SampleData {
    /// 6'0" → 182.88 cm, 200 lb → 90.72 kg (stored metric; the UI converts to imperial at the edge).
    static let profile = Profile(
        name: "Ricardo",
        sex: .male,
        ageYears: 20,
        heightCm: 182.88,
        weightKg: 90.72,
        createdAt: "2026-01-04T16:20:00.000Z"
    )

    static let whoopSummary = WhoopSummary(
        recoveryPct: 94,
        recoveryState: .green,
        hrvMs: 128,
        hrvBaselineMs: 110,
        rhrBpm: 49,
        rhrBaselineBpm: 52,
        respiratoryRate: 14.8,
        spo2Pct: 97,
        skinTempC: 33.4,
        sleepPerformancePct: 100,
        sleepHours: 8.4,
        dayStrain: 17.9,
        calories: 2658,
        steps: WhoopSteps(count: 5322, baseline30d: 6363),
        updatedAt: "2026-06-06T13:05:00.000Z",
        recordedAt: "2026-06-06T05:30:00.000Z"
    )

    static let sleepDetail = SleepDetail(
        date: "2026-06-06",
        startedAt: "2026-06-05T22:38:00.000Z",
        endedAt: "2026-06-06T07:52:00.000Z",
        totalSleepMs: 30_120_000,
        timeInBedMs: 33_240_000,
        performancePct: 100,
        consistencyPct: 65,
        efficiencyPct: 92,
        latencyMs: 300_000,
        restorativeMs: 16_620_000,
        respiratoryRate: nil,
        stages: sleepStages,
        disturbances: 18,
        hours: "8:22",
        hoursBaseline: "8:00",
        hoursNeeded: "8:24",
        durationInBed: "9:14",
        restorative: "4:37",
        latency: "0:05",
        wakeEvents: 18,
        performancePctExt: 100,
        efficiencyPctExt: 92,
        consistencyPctExt: 65,
        hrCurve: sleepHrCurve,
        windowStart: "2026-06-05T22:38:00.000Z",
        windowEnd: "2026-06-06T07:52:00.000Z",
        sleepStress: sleepStress
    )

    /// Per-stage durations + shares (REM 27 / light 42 / SWS 22 / awake 9). Includes typical-range
    /// bands as fractions so the stage bars render their "normal" markers.
    static let sleepStages = SleepStages(
        remMs: 8_132_400,
        lightMs: 12_650_400,
        swsMs: 6_626_400,
        wakeMs: 3_120_000,
        remPct: 27,
        lightPct: 42,
        swsPct: 22,
        wakePct: 9,
        remRange: SleepStageRange(lower: 0.18, upper: 0.28),
        lightRange: SleepStageRange(lower: 0.40, upper: 0.55),
        swsRange: SleepStageRange(lower: 0.12, upper: 0.23),
        wakeRange: SleepStageRange(lower: 0.04, upper: 0.12)
    )

    /// Overnight heart-rate curve: a gentle dip into deep sleep then a wake-up rise (bpm 48…62),
    /// sampled across the window so the sleep HR chart has a real shape.
    static let sleepHrCurve: [SleepHrPoint] = [
        SleepHrPoint(x: 0.00, bpm: 61, clock: "10:38 PM"),
        SleepHrPoint(x: 0.08, bpm: 57, clock: "11:22 PM"),
        SleepHrPoint(x: 0.16, bpm: 54, clock: "12:06 AM"),
        SleepHrPoint(x: 0.25, bpm: 51, clock: "12:50 AM"),
        SleepHrPoint(x: 0.34, bpm: 49, clock: "1:34 AM"),
        SleepHrPoint(x: 0.42, bpm: 48, clock: "2:18 AM"),
        SleepHrPoint(x: 0.50, bpm: 50, clock: "3:02 AM"),
        SleepHrPoint(x: 0.58, bpm: 49, clock: "3:46 AM"),
        SleepHrPoint(x: 0.67, bpm: 51, clock: "4:30 AM"),
        SleepHrPoint(x: 0.75, bpm: 53, clock: "5:14 AM"),
        SleepHrPoint(x: 0.84, bpm: 56, clock: "5:58 AM"),
        SleepHrPoint(x: 0.92, bpm: 59, clock: "6:42 AM"),
        SleepHrPoint(x: 1.00, bpm: 62, clock: "7:26 AM"),
    ]

    /// Overnight sleep-stress: a low headline (4%) with a mostly-low 0–3 curve and a high/medium/low
    /// breakdown, matching a good night.
    static let sleepStress = SleepStress(
        overallPct: 4,
        curve: sleepStressCurve,
        breakdown: SleepStressBreakdown(
            high: SleepStressBand(pctDisplay: "2%", timeDisplay: "0:11"),
            medium: SleepStressBand(pctDisplay: "13%", timeDisplay: "1:05"),
            low: SleepStressBand(pctDisplay: "85%", timeDisplay: "7:06")
        )
    )

    static let sleepStressCurve: [SleepStressPoint] = [
        SleepStressPoint(x: 0.00, level: 1.0, clock: "10:38 PM", band: "LOW"),
        SleepStressPoint(x: 0.20, level: 0.6, clock: "12:30 AM", band: "LOW"),
        SleepStressPoint(x: 0.40, level: 0.3, clock: "2:10 AM", band: "LOW"),
        SleepStressPoint(x: 0.55, level: 1.4, clock: "3:25 AM", band: "MEDIUM"),
        SleepStressPoint(x: 0.70, level: 0.5, clock: "4:40 AM", band: "LOW"),
        SleepStressPoint(x: 0.85, level: 0.9, clock: "5:55 AM", band: "LOW"),
        SleepStressPoint(x: 1.00, level: 1.2, clock: "7:26 AM", band: "MEDIUM"),
    ]

    static let strainDetail = StrainDetail(
        date: "2026-06-06",
        score: 17.9,
        target: StrainTarget(value: 17.9, optimalLower: 14.0, optimalUpper: 18.0),
        zone13Ms: 9_900_000,
        zone13BaselineMs: 8_400_000,
        zone45Ms: 1_980_000,
        zone45BaselineMs: 1_500_000,
        strengthActivityMs: 3_600_000,
        strengthActivityBaselineMs: 2_700_000,
        steps: 5322,
        stepsBaseline: 6363,
        kilojoules: nil,
        calories: nil,
        workoutsCount: 2
    )

    /// Demo behavior→outcome impacts (restated like WHOOP's own) for the populated container.
    static let behaviorImpacts: [WhoopBehaviorImpact] = [
        WhoopBehaviorImpact(id: "demo-alcohol", name: "Alcohol", impactDisplay: "−12%", direction: .negative),
        WhoopBehaviorImpact(id: "demo-daylight", name: "Daylight eating", impactDisplay: "+7%", direction: .positive),
        WhoopBehaviorImpact(id: "demo-latemeal", name: "Late meal", impactDisplay: "−5%", direction: .negative),
        WhoopBehaviorImpact(id: "demo-caffeine", name: "Caffeine after 2pm", impactDisplay: nil, direction: .insufficient),
    ]

    /// Demo sleep-need coaching (minutes) for the populated container.
    static let sleepNeed = WhoopSleepNeed(
        recommendedMinutes: 8 * 60 + 12, baselineMinutes: 7 * 60 + 40,
        debtMinutes: 18, strainMinutes: 22, napCreditMinutes: 8
    )

    static let stressDetail = StressDetail(
        date: "2026-06-06",
        currentStress: 1.1,
        stressState: "RELAXED",
        minStress: 0.2,
        maxStress: 2.4,
        lastUpdated: "5:19 PM",
        graph: stressGraph,
        trend: "Lower than your 30-day average."
    )

    static let stressGraph: [StressGraphPoint] = [
        StressGraphPoint(time: "6:00 AM", value: 0.4),
        StressGraphPoint(time: "8:00 AM", value: 1.6),
        StressGraphPoint(time: "10:00 AM", value: 2.1),
        StressGraphPoint(time: "12:00 PM", value: 1.3),
        StressGraphPoint(time: "2:00 PM", value: 2.4),
        StressGraphPoint(time: "4:00 PM", value: 1.0),
        StressGraphPoint(time: "6:00 PM", value: 0.7),
        StressGraphPoint(time: "8:00 PM", value: 0.3),
    ]

    static let goals = Goals(
        calorieGoal: 2800, proteinGoal: 200, fatGoal: 78, carbGoal: 300, stepsGoal: 10_000
    )

    /// Saved reusable meals (favorites) for the "Saved & recent" list.
    static let savedMeals: [SavedMeal] = [
        SavedMeal(
            id: "saved-1",
            name: "Whey protein shake",
            calories: 180, proteinG: 40, carbsG: 4, fatG: 1.5,
            createdAt: "2026-04-12T08:00:00.000Z",
            lastUsedAt: "2026-06-06T10:15:00.000Z",
            useCount: 47
        ),
        SavedMeal(
            id: "saved-2",
            name: "Chicken, rice, and veggies",
            calories: 640, proteinG: 55, carbsG: 68, fatG: 14,
            createdAt: "2026-04-18T12:00:00.000Z",
            lastUsedAt: "2026-06-05T12:40:00.000Z",
            useCount: 31
        ),
        SavedMeal(
            id: "saved-3",
            name: "Overnight oats",
            calories: 410, proteinG: 24, carbsG: 52, fatG: 12,
            createdAt: "2026-05-02T07:30:00.000Z",
            lastUsedAt: "2026-06-04T07:35:00.000Z",
            useCount: 18
        ),
    ]

    /// Resolved + in-flight food-log lines for the demo day (most recent listed first).
    static let foodLogLines: [(text: String, items: [LoggedFoodItem], status: FoodEntryStatus)] = [
        (
            "salmon, rice, and broccoli",
            [LoggedFoodItem(name: "Salmon, rice, and broccoli", calories: 650, proteinG: 46,
                            carbsG: 62, fatG: 24, sugarG: 3, fiberG: 6, sodiumMg: 540,
                            citations: ["https://fdc.nal.usda.gov"],
                            assumptions: "Assumed a 6 oz fillet, 1 cup cooked rice, and a side of broccoli. Estimates lean high to protect your deficit.",
                            confidenceScore: 72)],
            .resolved
        ),
        (
            "16 oz water",
            [LoggedFoodItem(name: "16 oz water", calories: 0, citations: [],
                            assumptions: "Logged as water, excluded from calories.",
                            confidenceScore: 100, isWaterEntry: true, waterMilliliters: 473)],
            .resolved
        ),
        (
            "greek yogurt with blueberries",
            [LoggedFoodItem(name: "Greek yogurt + blueberries", calories: 210, proteinG: 22,
                            carbsG: 24, fatG: 3, sugarG: 16, fiberG: 2, sodiumMg: 65,
                            assumptions: "Assumed 1 cup nonfat Greek yogurt and a handful of blueberries.",
                            confidenceScore: 55)],
            .resolved
        ),
        (
            "chicken burrito bowl with guac",
            [LoggedFoodItem(name: "Chicken burrito bowl with guac", calories: 720, proteinG: 52,
                            carbsG: 74, fatG: 22, sugarG: 5, fiberG: 11, sodiumMg: 1320,
                            citations: ["https://www.chipotle.com/nutrition-calculator"],
                            assumptions: "Assumed brown rice, black beans, chicken, salsa, and a side of guac. Estimates lean high to protect your deficit.",
                            confidenceScore: 68)],
            .resolved
        ),
    ]

    /// Saved nicknamed shortcuts for the inline quick-add row (most-used first).
    static let foodShortcuts: [FoodShortcut] = [
        FoodShortcut(
            nickname: "Regular Chipotle order",
            items: [LoggedFoodItem(name: "Chicken burrito bowl with guac", calories: 980, proteinG: 62,
                                   carbsG: 96, fatG: 34, sugarG: 6, fiberG: 14, sodiumMg: 1740,
                                   citations: ["https://www.chipotle.com/nutrition-calculator"],
                                   confidenceScore: 78)],
            source: "log", useCount: 23,
            createdAt: "2026-04-10T18:00:00.000Z", updatedAt: "2026-06-05T18:30:00.000Z"
        ),
        FoodShortcut(
            nickname: "Morning protein shake",
            items: [LoggedFoodItem(name: "Whey + banana + PB", calories: 360, proteinG: 44,
                                   carbsG: 30, fatG: 9, confidenceScore: 85)],
            source: "log", useCount: 41,
            createdAt: "2026-03-22T08:00:00.000Z", updatedAt: "2026-06-06T08:05:00.000Z"
        ),
    ]

    #if DEBUG
    /// One meal template: display text + macro tuple (kcal, protein g, carbs g, fat g).
    private typealias Meal = (text: String, kcal: Double, p: Double, c: Double, f: Double)

    private static let historyBreakfasts: [Meal] = [
        ("Overnight oats with berries", 410, 24, 52, 12),
        ("Three eggs, toast, and avocado", 470, 26, 32, 26),
        ("Greek yogurt, granola, and honey", 350, 27, 45, 6),
        ("Protein shake and a banana", 320, 40, 34, 5),
        ("Egg-white veggie scramble", 300, 30, 12, 14),
    ]
    private static let historyLunches: [Meal] = [
        ("Chicken, rice, and veggies", 640, 55, 68, 14),
        ("Turkey sandwich and an apple", 560, 38, 62, 16),
        ("Chipotle chicken bowl", 780, 52, 78, 26),
        ("Salmon salad with quinoa", 590, 42, 44, 24),
        ("Beef and broccoli with rice", 700, 48, 72, 22),
    ]
    private static let historyDinners: [Meal] = [
        ("Steak, potatoes, and greens", 720, 52, 58, 30),
        ("Pasta with chicken and marinara", 680, 46, 82, 16),
        ("Tofu stir-fry with rice", 610, 30, 74, 20),
        ("Chicken burrito bowl with guac", 720, 52, 74, 22),
        ("Grilled shrimp tacos", 640, 40, 66, 22),
    ]
    private static let historySnacks: [Meal] = [
        ("Whey protein shake", 180, 40, 4, 2),
        ("Apple and peanut butter", 260, 8, 30, 14),
        ("Cottage cheese and pineapple", 220, 24, 20, 4),
        ("Handful of almonds", 170, 6, 6, 15),
    ]

    private static func historyLine(_ meal: Meal) -> (text: String, items: [LoggedFoodItem], status: FoodEntryStatus) {
        (meal.text,
         [LoggedFoodItem(name: meal.text, calories: meal.kcal, proteinG: meal.p,
                         carbsG: meal.c, fatG: meal.f, confidenceScore: 70)],
         .resolved)
    }

    /// `days` prior days of logged meals (day 1 = yesterday), each a rotating B/L/D plus a snack on most
    /// days, for `FoodLogStore.seedHistory`. Deterministic (keyed to the day index, no RNG), giving a
    /// natural spread of daily totals under the 2,800 goal so the "Last 14 days" chart reads as real.
    static func foodLogHistory(days: Int) -> [(daysAgo: Int, lines: [(text: String, items: [LoggedFoodItem], status: FoodEntryStatus)])] {
        (1...days).map { d in
            var meals: [Meal] = [
                historyBreakfasts[d % historyBreakfasts.count],
                historyLunches[(d + 1) % historyLunches.count],
                historyDinners[(d + 2) % historyDinners.count],
            ]
            if d % 3 != 0 { meals.append(historySnacks[d % historySnacks.count]) }
            if d % 5 == 0 { meals.append(historySnacks[(d + 2) % historySnacks.count]) }
            return (daysAgo: d, lines: meals.map(historyLine))
        }
    }
    #endif

    /// Parsed + in-flight workout sessions for the demo day (most recent listed first).
    static let workoutLogSessions: [(title: String?, rawText: String, exercises: [WorkoutExercise], status: WorkoutEntryStatus, lowConfidence: Bool)] = [
        (
            "Push day",
            "Bench 3x10 @135, incline DB 10,10,8 @50, cable fly 3x15",
            [
                WorkoutExercise(name: "Barbell Bench Press", note: "felt strong", sets: [
                    WorkoutSet(reps: 12, weight: 95, weightUnit: "lb", isWarmup: true, raw: "warmup 12@95"),
                    WorkoutSet(reps: 10, weight: 135, weightUnit: "lb", raw: "10@135"),
                    WorkoutSet(reps: 10, weight: 135, weightUnit: "lb", raw: "10@135"),
                    WorkoutSet(reps: 8, weight: 135, weightUnit: "lb", rpe: 8, raw: "8@135 @8"),
                ]),
                WorkoutExercise(name: "Incline Dumbbell Press", group: "A", sets: [
                    WorkoutSet(reps: 10, weight: 50, weightUnit: "lb", raw: "10@50"),
                    WorkoutSet(reps: 10, weight: 50, weightUnit: "lb", raw: "10@50"),
                    WorkoutSet(reps: 8, weight: 50, weightUnit: "lb", isDropSet: true, raw: "8@50 drop"),
                ]),
                WorkoutExercise(name: "Cable Fly", group: "A", sets: [
                    WorkoutSet(reps: 15, weight: 30, weightUnit: "lb", raw: "15@30"),
                    WorkoutSet(reps: 15, weight: 30, weightUnit: "lb", raw: "15@30"),
                    WorkoutSet(reps: 15, weight: 30, weightUnit: "lb", raw: "15@30"),
                ]),
            ],
            .resolved,
            false
        ),
        (
            nil,
            "squats 5x5 @225",
            [],
            .pending,
            false
        ),
    ]

    /// Saved nicknamed workout shortcuts for the inline quick-add row (most-used first).
    static let workoutShortcuts: [WorkoutShortcut] = [
        WorkoutShortcut(
            nickname: "Pull day",
            exercises: [
                WorkoutExercise(name: "Deadlift", sets: [
                    WorkoutSet(reps: 5, weight: 315, weightUnit: "lb", raw: "5@315"),
                ]),
                WorkoutExercise(name: "Pull-up", sets: [
                    WorkoutSet(reps: 10, raw: "bodyweight x10"),
                ]),
                WorkoutExercise(name: "Barbell Row", sets: [
                    WorkoutSet(reps: 8, weight: 155, weightUnit: "lb", raw: "8@155"),
                ]),
            ],
            useCount: 14,
            createdAt: "2026-04-10T18:00:00.000Z", updatedAt: "2026-06-05T18:30:00.000Z"
        ),
        WorkoutShortcut(
            nickname: "Leg day",
            exercises: [
                WorkoutExercise(name: "Back Squat", sets: [
                    WorkoutSet(reps: 5, weight: 225, weightUnit: "lb", raw: "5@225"),
                ]),
                WorkoutExercise(name: "Romanian Deadlift", sets: [
                    WorkoutSet(reps: 10, weight: 185, weightUnit: "lb", raw: "10@185"),
                ]),
            ],
            useCount: 9,
            createdAt: "2026-03-22T08:00:00.000Z", updatedAt: "2026-06-06T08:05:00.000Z"
        ),
    ]

    /// Recovery % trend: the cyan recovery line on the Whoop/Overview trends card.
    static let recoveryTrend: [WhoopHistoryPoint] = trend(metricBase: 78, values: [71, 64, 83, 88, 76, 91, 94])

    /// HRV (ms) trend.
    static let hrvTrend: [WhoopHistoryPoint] = trend(metricBase: 110, values: [98, 92, 112, 121, 105, 124, 128])

    /// Resting HR (bpm) trend.
    static let rhrTrend: [WhoopHistoryPoint] = trend(metricBase: 52, values: [54, 55, 51, 50, 53, 50, 49])

    /// Day strain (0–21) trend.
    static let strainTrend: [WhoopHistoryPoint] = trend(metricBase: 14, values: [12.4, 9.8, 15.1, 16.6, 11.2, 18.3, 17.9])

    /// Build a 7-point dated trend ending today (oldest → newest), one value per day.
    private static func trend(metricBase: Double, values: [Double]) -> [WhoopHistoryPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)
        let n = values.count
        return values.enumerated().map { index, value in
            let date = calendar.date(byAdding: .day, value: -(n - 1 - index), to: today) ?? today
            let comps = calendar.dateComponents([.year, .month, .day], from: date)
            let key = String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
            return WhoopHistoryPoint(date: key, value: value)
        }
    }

    /// The demo's reference "today": the current day, so the seeded record always reads as current
    /// (greeting, date wheel, Whoop snapshot, and every trend land on today, not a stale fixed date).
    /// Anchored at local noon so the YYYY-MM-DD day-key math is timezone-stable.
    static let referenceDate: Date = {
        let cal = Calendar.current
        return cal.date(byAdding: .hour, value: 12, to: cal.startOfDay(for: Date())) ?? Date()
    }()

    static let insightsDayCount = 21

    /// Recovery % per day (0–100), oldest → newest. The dependent metric the cards correlate against.
    static let recoveryHistory: [Double] = [
        62, 71, 55, 78, 84, 49, 66, 73, 88, 72,
        58, 70, 92, 76, 64, 83, 90, 69, 60, 85, 94,
    ]

    /// ~18 weeks of daily recovery % (0–100), oldest → newest, for the calendar heatmap. A deterministic
    /// synthetic series (a calm wave plus variation, clamped 38–97) so the demo grid reads realistically;
    /// display-only, never the user's real data.
    static let recoveryCalendar: [Double] = (0..<126).map { i in
        let wave = 65 + 18 * sin(Double(i) * 0.13) + 11 * sin(Double(i) * 0.91)
        return min(97, max(38, wave.rounded()))
    }

    /// HRV (ms) per day: moves with recovery (strong positive).
    static let hrvHistory: [Double] = [
        106, 119, 103, 117, 121, 99, 116, 119, 134, 120,
        115, 118, 133, 121, 111, 134, 138, 124, 117, 123, 126,
    ]

    /// Resting HR (bpm) per day: moves against recovery (negative; low RHR ↔ high recovery).
    static let rhrHistory: [Double] = [
        51, 49, 54, 49, 50, 53, 53, 51, 46, 49,
        54, 50, 49, 49, 50, 49, 49, 50, 50, 48, 49,
    ]

    /// Sleep performance % per day: tracks recovery (strong positive).
    static let sleepPerformanceHistory: [Double] = [
        89, 82, 77, 85, 87, 84, 81, 91, 96, 84,
        87, 82, 100, 84, 84, 89, 93, 96, 89, 92, 100,
    ]

    /// Day strain (0–21) per day: same-day strain ↔ recovery is weak; the signal is the lagged pairing
    /// (a high-strain day tends to precede a lower next-day recovery).
    static let strainHistory: [Double] = [
        12.3, 14.5, 15.0, 11.2, 14.6, 13.7, 10.2, 11.2, 13.5, 15.9,
        9.8, 9.3, 9.2, 15.5, 12.9, 7.6, 16.3, 16.9, 12.5, 11.4, 10.2,
    ]

    /// 28 daily weigh-ins in pounds, oldest → newest (the last is `referenceDate`). A gentle cut with
    /// natural noise. Feeds `GoalPaceMath.trendWeight` for the Overview Goal-Pace card.
    static let weightHistoryLb: [Double] = [
        187.8, 188.4, 187.2, 187.6, 186.9, 188.1, 187.0,
        186.4, 187.1, 186.0, 186.6, 185.8, 186.9, 185.7,
        185.9, 185.2, 186.0, 185.1, 184.8, 185.6, 184.7,
        185.0, 184.4, 184.9, 184.1, 184.6, 183.8, 184.0,
    ]

    /// The user's own dated goal for the sample: reach 175 lb. A round, sustainable-looking lose goal
    /// below the current trend, set by the user (never a recommendation).
    static let goalTargetWeightLb: Double = 175

    /// The user's own target date for that goal: a local YYYY-MM-DD key 11 weeks (77 days) past
    /// `referenceDate`. The sample trend rate (~0.90 lb/week) closely matches the rate this ~10 lb gap
    /// demands (~0.92 lb/week), so the card reads on-track (the neutral-positive demo case).
    static let goalTargetDateKey: String = {
        let calendar = Calendar.current
        let target = calendar.date(byAdding: .day, value: 77, to: calendar.startOfDay(for: referenceDate)) ?? referenceDate
        let c = calendar.dateComponents([.year, .month, .day], from: target)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }()
}
