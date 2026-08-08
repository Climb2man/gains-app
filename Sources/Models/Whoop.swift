import Foundation

/// Recovery zone derived from Whoop's gauge fill style.
enum WhoopRecoveryState: String, Codable, Equatable, Sendable {
    case green = "GREEN"
    case yellow = "YELLOW"
    case red = "RED"
}

/// Daily step count + 30-day baseline.
struct WhoopSteps: Codable, Equatable, Sendable {
    var count: Int
    var baseline30d: Int?
}

/// Normalized snapshot rendered on the dashboard / Recovery tab. Every field is
/// optional. A missing tile leaves the metric blank rather than crashing.
struct WhoopSummary: Codable, Equatable, Sendable {
    var recoveryPct: Double?
    var recoveryState: WhoopRecoveryState?
    var hrvMs: Double?
    var hrvBaselineMs: Double?
    var rhrBpm: Double?
    var rhrBaselineBpm: Double?
    var respiratoryRate: Double?
    var spo2Pct: Double?
    var skinTempC: Double?
    var sleepPerformancePct: Double?
    /// Sleep duration in hours (ms→hours, 2-decimal).
    var sleepHours: Double?
    /// Day strain on Whoop's 0–21 scale.
    var dayStrain: Double?
    /// Whole-day energy burned (kcal), the one daily energy figure Whoop surfaces.
    var calories: Double?
    /// Daily steps + 30-day baseline; nil when the tile is absent/non-numeric.
    var steps: WhoopSteps?
    /// ISO time this snapshot was assembled on-device.
    var updatedAt: String?
    /// The physiological day's start ("cycle" start) as an ISO timestamp.
    var recordedAt: String?
}

/// One sampled point on the overnight heart-rate curve.
struct SleepHrPoint: Codable, Equatable, Sendable {
    /// Horizontal position 0–1 across the sleep window (Whoop's `position_x`).
    var x: Double
    /// Heart rate (bpm), parsed from the point's `value_display`.
    var bpm: Double
    /// Verbatim clock label for the point ("9:45 PM").
    var clock: String
}

/// WHOOP's sleep-need coaching for the night (`/coaching-service/v2/sleepneed`). All durations in
/// minutes. WHOOP's own computed need, restated; never a prescription.
struct WhoopSleepNeed: Codable, Equatable, Sendable {
    /// Recommended time in bed for the standard 85%-performance tier, in minutes.
    var recommendedMinutes: Int?
    /// Components of the need (minutes): baseline + sleep debt + strain add-on − nap credit.
    var baselineMinutes: Int?
    var debtMinutes: Int?
    var strainMinutes: Int?
    var napCreditMinutes: Int?
}

/// WHOOP's stored body measurement (`/developer/v2/user/measurement/body`). These are the values
/// WHOOP holds for the account, which is where a connected smart scale's readings land — so this is
/// the app's weight source now that HealthKit is unavailable on a free Apple ID.
///
/// The path is WHOOP's OFFICIAL API schema (`height_meter` / `weight_kilogram` / `max_heart_rate`)
/// and it answers the app's own token. The private `/users-service/v1/users/{id}/profile` route
/// carries the same two numbers, but wraps them in the full profile (name, birthday, city, gender)
/// and needs the numeric `custom:user_id` in the path — more data, more to break. Prefer this one.
struct WhoopBodyMeasurement: Codable, Equatable, Sendable {
    /// Body mass in kilograms. Always > 0; the fetch rejects 0 (an empty/secondary WHOOP account
    /// answers with `weight: 0.0`, which must never be logged as a real weigh-in).
    var weightKg: Double
    /// Height in metres, or nil when WHOOP has none.
    var heightMeters: Double?
    /// WHOOP's max heart rate (bpm), or nil.
    var maxHeartRate: Int?
}

/// One behavior → outcome association WHOOP computed (e.g. "Alcohol · −12%"), restated verbatim.
/// The app never derives or diagnoses it. Too little data surfaces as `.insufficient` (no number).
struct WhoopBehaviorImpact: Codable, Equatable, Sendable, Identifiable {
    enum Direction: String, Codable, Sendable { case positive, negative, insufficient }
    /// Stable id for the row (WHOOP's impact_uuid).
    var id: String
    /// Behavior label, verbatim ("Daylight Eating", "Alcohol").
    var name: String
    /// WHOOP's own percentage string ("+7%", "−12%"); nil when insufficient data.
    var impactDisplay: String?
    var direction: Direction
}

/// The live heart rate from the strap (the `/health-tab-bff` LIVE_HR tile). Restated as-is; never
/// classified.
struct WhoopLiveHr: Codable, Equatable, Sendable {
    /// Current beats per minute, or nil when the strap isn't streaming a value.
    var bpm: Int?
    /// HR zone 0…5 if reported.
    var zone: Int?
    /// True when actively streaming (vs a last-known value).
    var isRecording: Bool
    /// Clock/ISO string of the last reading, for staleness, shown verbatim if present.
    var lastUpdated: String?
}

/// One sampled point on the overnight sleep-stress curve, carried only by
/// `SleepStress.curve`.
struct SleepStressPoint: Codable, Equatable, Sendable {
    /// Horizontal position 0–1 across the sleep window (`position_x`).
    var x: Double
    /// Stress level on Whoop's 0–3 scale, parsed from `value_display`.
    var level: Double
    /// Verbatim clock label ("9:44 PM"), from `primary_contextual_display`.
    var clock: String
    /// Band word ("LOW" | "MEDIUM" | "HIGH"), from `secondary_contextual_display`.
    var band: String
}

/// A stage's "typical range" band, as fractions (0–1) of total sleep. Kept raw so the UI converts.
struct SleepStageRange: Codable, Equatable, Sendable {
    var lower: Double
    var upper: Double
}

/// One stress band's display strings (HIGH/MEDIUM/LOW).
struct SleepStressBand: Codable, Equatable, Sendable {
    var pctDisplay: String
    var timeDisplay: String
}

/// Per-band time + share, keyed HIGH / MEDIUM / LOW.
struct SleepStressBreakdown: Codable, Equatable, Sendable {
    var high: SleepStressBand?
    var medium: SleepStressBand?
    var low: SleepStressBand?
}

/// Overnight sleep-stress breakdown (lives in the sleep deep-dive, not a stress endpoint). Every
/// part optional.
struct SleepStress: Codable, Equatable, Sendable {
    /// Headline sleep-stress %, from the SLEEP STRESS card's arrow_stat ("0%").
    var overallPct: Double?
    /// The overnight 0–3 stress curve, oldest → newest (by `x`).
    var curve: [SleepStressPoint]?
    /// Per-band time + share, keyed HIGH / MEDIUM / LOW.
    var breakdown: SleepStressBreakdown?
}

/// Per-stage durations + shares + optional typical-range bands.
struct SleepStages: Codable, Equatable, Sendable {
    var remMs: Double?
    var lightMs: Double?
    var swsMs: Double?
    var wakeMs: Double?
    var remPct: Double?
    var lightPct: Double?
    var swsPct: Double?
    var wakePct: Double?
    /// Per-stage "typical range" bands as fractions (0–1) of total sleep; nil when the bar omits the
    /// range. Kept raw; the UI converts.
    var remRange: SleepStageRange?
    var lightRange: SleepStageRange?
    var swsRange: SleepStageRange?
    var wakeRange: SleepStageRange?
}

/// Detailed sleep from /deep-dive/sleep/last-night. Every field is optional. A changed or missing
/// tile degrades rather than throws.
///
///   • `totalSleepMs` is time asleep (the "HOURS OF SLEEP" stat, e.g. 8:22).
///   • `timeInBedMs` is the stage card's total duration (includes the awake stage), so it's larger.
///   • `respiratoryRate` isn't exposed by this endpoint and stays nil.
struct SleepDetail: Codable, Equatable, Sendable {
    var date: String
    var startedAt: String?
    var endedAt: String?
    /// Time asleep (REM + light + SWS), from "HOURS OF SLEEP".
    var totalSleepMs: Double?
    /// Time in bed (stage card's total duration; includes awake time).
    var timeInBedMs: Double?
    var performancePct: Double?
    var consistencyPct: Double?
    var efficiencyPct: Double?
    /// Time it took to fall asleep ("SLEEP LATENCY"), in ms.
    var latencyMs: Double?
    /// Restorative (REM + SWS) sleep duration ("RESTORATIVE SLEEP"), in ms.
    var restorativeMs: Double?
    /// Breaths/min: not exposed by this endpoint; always nil here.
    var respiratoryRate: Double?
    var stages: SleepStages
    var disturbances: Double?

    /// Time-asleep display from "HOURS OF SLEEP" ("8:22"), kept verbatim.
    var hours: String?
    /// 30-day baseline time-asleep ("8:00").
    var hoursBaseline: String?
    /// Sleep-needed display from the HOURS VS. NEEDED card's SLEEP NEEDED bar ("8:24").
    var hoursNeeded: String?
    /// Time-in-bed display from the stages card's `duration_display` ("9:14").
    var durationInBed: String?
    /// Restorative-sleep display ("RESTORATIVE SLEEP", "4:37"), verbatim.
    var restorative: String?
    /// Sleep-latency display ("SLEEP LATENCY", "0:05"), verbatim.
    var latency: String?
    /// Wake-event count ("WAKE EVENTS", parsed from "18").
    var wakeEvents: Double?
    /// Sleep performance % from the HOURS VS. NEEDED card's arrow_stat ("100%").
    var performancePctExt: Double?
    /// Sleep efficiency % from the SLEEP EFFICIENCY card ("92%").
    var efficiencyPctExt: Double?
    /// Sleep consistency % from the SLEEP CONSISTENCY card ("65%").
    var consistencyPctExt: Double?
    /// The overnight heart-rate curve, merged across all five stage plots, sorted by `x`.
    var hrCurve: [SleepHrPoint]?
    /// Sleep window start, from the header destination params (ISO).
    var windowStart: String?
    /// Sleep window end, from the header destination params (ISO).
    var windowEnd: String?
    /// Overnight sleep-stress: headline %, 0–3 curve, and HIGH/MED/LOW breakdown.
    var sleepStress: SleepStress?
}

/// Strain target band.
struct StrainTarget: Codable, Equatable, Sendable {
    var value: Double?
    var optimalLower: Double?
    var optimalUpper: Double?
}

/// Detailed strain from /home-service/v1/deep-dive/strain.
///
/// This endpoint carries no calories/kilojoules and no daily-average BPM, so `kilojoules`/`calories`
/// stay `nil`, never fabricated from zone times.
struct StrainDetail: Codable, Equatable, Sendable {
    var date: String
    var score: Double?
    var target: StrainTarget
    /// Today's time (ms) in HR zones 1–3 (light/moderate).
    var zone13Ms: Double?
    /// 30-day baseline time (ms) in HR zones 1–3.
    var zone13BaselineMs: Double?
    /// Today's time (ms) in HR zones 4–5 (hard/max).
    var zone45Ms: Double?
    /// 30-day baseline time (ms) in HR zones 4–5.
    var zone45BaselineMs: Double?
    /// Today's strength-activity time (ms), from "STRENGTH ACTIVITY TIME".
    var strengthActivityMs: Double?
    /// 30-day baseline strength-activity time (ms).
    var strengthActivityBaselineMs: Double?
    var steps: Double?
    /// 30-day baseline step count.
    var stepsBaseline: Double?
    /// Not in this endpoint. Always nil; never fabricated.
    var kilojoules: Double?
    /// Not in this endpoint. Always nil; never fabricated.
    var calories: Double?
    var workoutsCount: Int
}

/// Per-point sample of the day-long stress curve.
struct StressGraphPoint: Codable, Equatable, Sendable {
    /// Verbatim local clock label ("5:24 AM").
    var time: String
    /// Stress level on Whoop's 0–3 scale.
    var value: Double
}

/// Stress monitor detail. Every field is optional except `graph`, which is an empty
/// array (not nil) when no curve is present. No throw, ever.
struct StressDetail: Codable, Equatable, Sendable {
    var date: String
    /// Current stress level on Whoop's 0–3 scale (from the gauge).
    var currentStress: Double?
    /// Headline state string ("RELAXED" | "STRESSED" | "CALIBRATING" | …).
    var stressState: String?
    /// Lowest level seen across the day's curve.
    var minStress: Double?
    /// Highest level seen across the day's curve.
    var maxStress: Double?
    /// Clock label of the latest reading ("5:19 PM").
    var lastUpdated: String?
    /// The 24-h stress curve (downsampled), oldest → newest.
    var graph: [StressGraphPoint]
    /// Optional trend word/string vs. the prior period.
    var trend: String?
}
