import Foundation

enum GoalPaceMath {
    /// EWMA smoothing factor (Hacker's Diet value): newest day gets 10% weight, ~10-day time constant (1/alpha).
    /// Lower = smoother, higher = more reactive.
    static let defaultAlpha = 0.10

    /// Recent window (days) over which the trend slope gives the actual rate.
    static let defaultWindowDays = 14

    /// ±15% tolerance around the needed pace so week-to-week noise doesn't flip the
    /// behind/on-track/ahead pill. 0.85 ≤ ratio < 1.15 reads on-track.
    static let defaultTolerance = 0.15

    /// Minimum-data thresholds: below any of these we show "Not enough data yet" instead of a
    /// projection. Mirrors MacroFactor's ~14-day EWMA warm-up.
    static let minWeighIns = 8
    static let minSpanDays = 14
    static let minRunwayDays = 14
    static let minWindowDays = 7

    /// Below this magnitude (lb/week) the trend is treated as flat and no date is projected
    /// (a near-zero slope would project a false, wildly distant month).
    static let flatRateFloor = 0.05

    /// Cutoffs for flagging the user's target as fast (never blocked, never used to push a
    /// deficit): triggered when the required rate exceeds either bound.
    static let aggressivePctPerWeek = 0.01
    static let aggressiveLbPerWeek = 2.0

    /// Tiny epsilon to guard divisions (weeks-remaining, required rate). Never user-visible.
    static let epsilon = 1e-6

    /// EWMA of an ordered daily weigh-in series (pounds, oldest to newest). Seeds with the first
    /// weigh-in, then `T[i] = T[i-1] + α·(w[i] − T[i-1])`.
    ///
    /// Callers pass one value per logged day (already day-averaged); skipped calendar days are not
    /// interpolated. Returns an empty array for empty input.
    static func trendWeight(_ dailyWeighIns: [Double], alpha: Double = defaultAlpha) -> [Double] {
        guard let first = dailyWeighIns.first else { return [] }
        var trend: [Double] = []
        trend.reserveCapacity(dailyWeighIns.count)
        var t = first
        trend.append(t)
        for w in dailyWeighIns.dropFirst() {
            t = t + alpha * (w - t)
            trend.append(t)
        }
        return trend
    }

    /// Actual weight-change rate in lb/week: the trend's endpoint difference over the recent window,
    /// clamped to available data. Positive = gaining, negative = losing.
    ///
    /// Slope is read off the smoothed trend, not raw scale weight (raw daily weight is dominated by
    /// water/glycogen noise). Returns 0 with fewer than 2 trend points (no slope to form).
    static func actualRateLbPerWeek(trend: [Double], windowDays: Int = defaultWindowDays) -> Double {
        guard trend.count >= 2 else { return 0 }
        let span = min(windowDays, trend.count - 1)
        guard span >= 1 else { return 0 }
        let endValue = trend[trend.count - 1]
        let startValue = trend[trend.count - 1 - span]
        let perDay = (endValue - startValue) / Double(span)
        return perDay * 7
    }

    /// The lb/week the target date demands, from current trend to target. Sign carries direction
    /// (negative = needs to drop, positive = needs to gain). `daysUntilTarget` is floored to an
    /// epsilon-week so the division is safe when the date is essentially today.
    static func requiredRateLbPerWeek(currentTrend: Double, targetWeight: Double, daysUntilTarget: Int) -> Double {
        let weeksRemaining = max(Double(daysUntilTarget) / 7, epsilon)
        return (targetWeight - currentTrend) / weeksRemaining
    }

    /// The three pace states. `behind` covers both "too slow in the right direction" and "flat or
    /// moving away"; the view words those separately but the band logic is the same.
    enum Status: Equatable {
        case behind
        case onTrack
        case ahead
    }

    /// Compare the actual rate to the required rate in the goal direction, within the tolerance band.
    ///
    /// `actual` and `required` are signed lb/week (negative = losing). `remaining` is the signed gap
    /// to close (`targetWeight − currentTrend`); its sign sets the goal direction, so both rates
    /// project onto it as ratio = (actual·goalDir) / |required|.
    /// ratio ≥ 1+tol → ahead · within ±tol → on-track · below (incl. ≤ 0, wrong way) → behind.
    static func status(actual: Double, required: Double, remaining: Double, tolerance: Double = defaultTolerance) -> Status {
        let goalDir: Double = remaining < 0 ? -1 : (remaining > 0 ? 1 : 0)
        let actualTowardGoal = actual * goalDir
        let requiredTowardGoal = abs(required)
        let ratio = actualTowardGoal / max(requiredTowardGoal, epsilon)

        if ratio >= 1 + tolerance { return .ahead }
        if ratio >= 1 - tolerance { return .onTrack }
        return .behind
    }

    /// Weeks until the trend reaches the target at the current actual rate, or `nil` when the trend
    /// is flat or moving the wrong way. Produced only when the actual rate's sign matches the
    /// remaining gap and clears the flat floor. Positive weeks-from-now; the caller labels the month.
    static func projectedWeeksToGoal(currentTrend: Double, targetWeight: Double, actualRate: Double) -> Double? {
        let remaining = targetWeight - currentTrend
        guard abs(remaining) > epsilon else { return 0 }
        guard sign(actualRate) == sign(remaining), abs(actualRate) > flatRateFloor else { return nil }
        return remaining / actualRate
    }

    /// Why a pace read may be withheld. `.ok` means we have enough to show a pill + projection.
    enum DataConfidence: Equatable {
        case ok
        case notEnoughData
    }

    /// Gate before showing any pace: enough weigh-ins, a wide enough span, enough runway to the
    /// target, and at least a week inside the recent window. Any failure → `.notEnoughData`.
    /// `spanDays` is the calendar span of the weigh-ins (first to last); `runwayDays` is days
    /// until the target date.
    static func dataConfidence(weighInCount: Int, spanDays: Int, runwayDays: Int, windowDays: Int = defaultWindowDays) -> DataConfidence {
        guard weighInCount >= minWeighIns else { return .notEnoughData }
        guard spanDays >= minSpanDays else { return .notEnoughData }
        guard runwayDays >= minRunwayDays else { return .notEnoughData }
        guard min(windowDays, spanDays) >= minWindowDays else { return .notEnoughData }
        return .ok
    }

    /// Whether the target date implies a fast required pace (flagged gently, never blocked or used
    /// to push a bigger deficit). True when the required rate exceeds 1% of body weight per week or
    /// 2 lb/week absolute.
    static func isAggressiveTarget(requiredRateLbPerWeek: Double, currentBodyWeightLb: Double) -> Bool {
        let magnitude = abs(requiredRateLbPerWeek)
        if magnitude > aggressiveLbPerWeek { return true }
        if currentBodyWeightLb > 0, magnitude > currentBodyWeightLb * aggressivePctPerWeek { return true }
        return false
    }

    /// −1 / 0 / +1 sign of a Double (0 for an exact 0, so a flat rate never claims a direction).
    private static func sign(_ x: Double) -> Double {
        if x > 0 { return 1 }
        if x < 0 { return -1 }
        return 0
    }
}
