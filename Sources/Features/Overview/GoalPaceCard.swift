import SwiftUI

/// Everything the card renders, pre-computed from the user's series and dated target. Built by the
/// `evaluate` factory so the math and copy assembly live in one testable place.
struct GoalPaceState: Equatable {
    /// The display state: drives the pill, the sentence, and which layers show.
    enum Kind: Equatable {
        case onTrack
        case ahead
        case behindSlow
        case behindFlat
        case goalReached
        case notEnoughData
    }

    let kind: Kind
    /// Current trend weight in lb (EWMA of weigh-ins), what we display rather than raw scale.
    let trendWeightLb: Double
    /// The user's target weight (lb) and the month label of their chosen date.
    let targetWeightLb: Double
    let targetMonth: String
    /// Their actual trend rate + the rate the date demands (both lb/week, magnitudes for copy).
    let actualRateLbPerWeek: Double
    let requiredRateLbPerWeek: Double
    /// Projected month they'd reach the target at the current trend, or nil (flat / wrong way).
    let projectedMonth: String?
    /// True when the chosen date implies a fast pace (> 1%/week or > 2 lb/week).
    let aggressiveTargetFlag: Bool
    /// The single descriptive sentence shown on the card.
    let sentence: String
    /// The full EWMA trend series (lb) for the sparkline. Empty in the not-enough-data minimal state.
    let trendSeriesLb: [Double]

    /// Run the pace math over the user's weigh-in series + dated target and assemble the display state.
    ///
    /// - weightHistoryLb: daily weigh-ins in pounds, oldest → newest (one value per logged day).
    /// - lastWeighInKey:  local YYYY-MM-DD of the last weigh-in (anchors the series' calendar span).
    /// - targetWeightLb / targetDateKey: the goal weight + chosen date (local key).
    /// - today: evaluation "now" (the demo reference date in `.sample`).
    static func evaluate(
        weightHistoryLb: [Double],
        lastWeighInKey: String,
        targetWeightLb: Double,
        targetDateKey: String,
        today: Date
    ) -> GoalPaceState? {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: today)
        guard
            Self.date(fromKey: lastWeighInKey) != nil,
            let targetDate = Self.date(fromKey: targetDateKey),
            !weightHistoryLb.isEmpty
        else { return nil }

        let targetMonth = Self.monthLabel(targetDate)

        let spanDays = max(0, weightHistoryLb.count - 1)
        let runwayDays = calendar.dateComponents([.day], from: todayStart, to: calendar.startOfDay(for: targetDate)).day ?? 0

        let trend = GoalPaceMath.trendWeight(weightHistoryLb)
        guard let currentTrend = trend.last else { return nil }

        let confidence = GoalPaceMath.dataConfidence(
            weighInCount: weightHistoryLb.count,
            spanDays: spanDays,
            runwayDays: runwayDays
        )
        if confidence == .notEnoughData {
            return GoalPaceState(
                kind: .notEnoughData,
                trendWeightLb: currentTrend,
                targetWeightLb: targetWeightLb,
                targetMonth: targetMonth,
                actualRateLbPerWeek: 0,
                requiredRateLbPerWeek: 0,
                projectedMonth: nil,
                aggressiveTargetFlag: false,
                sentence: "Keep logging your weight. After about two weeks of weigh-ins we can show your trend and how it compares to your \(targetMonth) goal. Daily weight bounces around too much to read on its own.",
                trendSeriesLb: trend
            )
        }

        let actualRate = GoalPaceMath.actualRateLbPerWeek(trend: trend)
        let requiredRate = GoalPaceMath.requiredRateLbPerWeek(
            currentTrend: currentTrend, targetWeight: targetWeightLb, daysUntilTarget: runwayDays
        )
        let remaining = targetWeightLb - currentTrend
        let goalDir: Double = remaining < 0 ? -1 : (remaining > 0 ? 1 : 0)

        let reached = (goalDir < 0 && currentTrend <= targetWeightLb)
            || (goalDir > 0 && currentTrend >= targetWeightLb)
            || goalDir == 0
        if reached {
            return GoalPaceState(
                kind: .goalReached,
                trendWeightLb: currentTrend,
                targetWeightLb: targetWeightLb,
                targetMonth: targetMonth,
                actualRateLbPerWeek: abs(actualRate),
                requiredRateLbPerWeek: abs(requiredRate),
                projectedMonth: nil,
                aggressiveTargetFlag: false,
                sentence: "Your weight trend has reached your goal of \(Self.lb(targetWeightLb)). Nice work. You can set a new goal, or switch to maintaining if you'd like to hold here.",
                trendSeriesLb: trend
            )
        }

        let status = GoalPaceMath.status(actual: actualRate, required: requiredRate, remaining: remaining)
        let projectedWeeks = GoalPaceMath.projectedWeeksToGoal(
            currentTrend: currentTrend, targetWeight: targetWeightLb, actualRate: actualRate
        )
        let projectedDate = projectedWeeks.map { calendar.date(byAdding: .day, value: Int(($0 * 7).rounded()), to: todayStart) ?? todayStart }
        let projectedMonth = projectedDate.map { Self.monthLabel($0) }

        let aggressive = GoalPaceMath.isAggressiveTarget(
            requiredRateLbPerWeek: requiredRate, currentBodyWeightLb: currentTrend
        )

        let kind: Kind
        switch status {
        case .ahead: kind = .ahead
        case .onTrack: kind = .onTrack
        case .behind: kind = projectedMonth == nil ? .behindFlat : .behindSlow
        }

        let actualMag = abs(actualRate)
        let requiredMag = abs(requiredRate)

        var sentence: String
        switch kind {
        case .onTrack:
            sentence = "Your weight trend is moving toward your goal at about the pace your date needs. At this trend you'd reach \(Self.lb(targetWeightLb)) around \(projectedMonth ?? targetMonth), right around your \(targetMonth) goal."
        case .ahead:
            sentence = "Your trend is moving toward your goal a bit faster than your date needs. At this pace you'd reach \(Self.lb(targetWeightLb)) around \(projectedMonth ?? targetMonth), ahead of your \(targetMonth) goal. This is just your own numbers; keep doing what feels sustainable."
        case .behindSlow:
            sentence = "Your trend is moving toward your goal, but slower than your \(targetMonth) date needs. About \(Self.rate(actualMag)) vs. the \(Self.rate(requiredMag)) that date would take. Your goal's still in reach if your trend continues, or you can give yourself more time by moving the date."
        case .behindFlat:
            sentence = "Your weight trend is about flat right now, so you're not on a path to \(Self.lb(targetWeightLb)) by \(targetMonth) yet. That's just what your numbers show. You can keep going, or pick a date that fits your current trend."
        case .goalReached, .notEnoughData:
            sentence = ""
        }

        if aggressive {
            sentence += " Reaching \(Self.lb(targetWeightLb)) by \(targetMonth) would mean about \(Self.rate(requiredMag)), faster than the 0.5 to 1% of body weight per week that's commonly suggested as sustainable. You might pick a later date."
        }

        return GoalPaceState(
            kind: kind,
            trendWeightLb: currentTrend,
            targetWeightLb: targetWeightLb,
            targetMonth: targetMonth,
            actualRateLbPerWeek: actualMag,
            requiredRateLbPerWeek: requiredMag,
            projectedMonth: projectedMonth,
            aggressiveTargetFlag: aggressive,
            sentence: sentence,
            trendSeriesLb: trend
        )
    }

    /// "175 lb", one-decimal; kg never shown (imperial rule).
    static func lb(_ value: Double) -> String { "\(Format.oneDecimal(value)) lb" }
    /// "0.9 lb/week", a descriptive rate magnitude, never a target to hit.
    static func rate(_ value: Double) -> String { "\(Format.oneDecimal(value)) lb/week" }

    /// Month-only label from a Date (e.g. "August"); day precision would be false here.
    static func monthLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMMM"
        return f.string(from: date)
    }

    /// Parse a local YYYY-MM-DD key → Date (no timezone drift), or nil if malformed.
    static func date(fromKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var c = DateComponents()
        c.year = parts[0]; c.month = parts[1]; c.day = parts[2]
        return Calendar.current.date(from: c)
    }
}

struct GoalPaceCard: View {
    let state: GoalPaceState

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Faint sleep-purple accent (the app's "weight" hue). Calm, never an alarm color.
    private var accent: Color { Theme.Chart.sleep }

    var body: some View {
        Card(metricAccent: accent) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                header

                if state.kind == .notEnoughData {
                    Txt(state.sentence, variant: .subhead, color: .labelSecondary)
                    trendChart(showGoalLine: false)
                } else {
                    Txt(state.sentence, variant: .subhead, color: .labelSecondary)
                    rateLine
                    trendChart(showGoalLine: true)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            CardHeader(title: "GOAL PACE", icon: "target")
            statusPill
            InfoDisclosure(
                title: "How this is calculated",
                body: "We smooth your daily weigh-ins into a trend weight, because daily scale weight bounces around with water and food and isn't a reliable read on its own. We compare how your trend is moving to the pace your own target date would take, and describe the gap. It's a mirror of your own numbers and your own goal."
            )
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        switch state.kind {
        case .onTrack:
            Pill(text: "ON TRACK", tone: .success)
        case .ahead:
            Pill(text: "AHEAD", tone: .success)
        case .goalReached:
            Pill(text: "GOAL REACHED", tone: .success)
        case .behindSlow, .behindFlat:
            Pill(text: "BEHIND", tone: .warning)
        case .notEnoughData:
            Pill(text: "NOT ENOUGH DATA YET", tone: .neutral)
        }
    }

    @ViewBuilder
    private var rateLine: some View {
        if state.kind == .behindSlow || state.kind == .behindFlat || state.kind == .onTrack || state.kind == .ahead {
            HStack(spacing: Theme.Spacing.sm) {
                rateChip(label: "Your trend", value: GoalPaceState.rate(state.actualRateLbPerWeek), color: accent)
                rateChip(label: "Date needs", value: GoalPaceState.rate(state.requiredRateLbPerWeek), color: Theme.Colors.labelSecondary)
            }
        }
    }

    private func rateChip(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Txt(label, variant: .footnote, color: .labelTertiary)
            HStack(spacing: Theme.Spacing.xs) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(value)
                    .font(Theme.Font.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.label)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .fill(Theme.Colors.surface2)
        )
    }

    private func trendChart(showGoalLine: Bool) -> some View {
        let series = state.trendSeriesLb
        let goal = showGoalLine ? state.targetWeightLb : nil
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            GeometryReader { geo in
                ZStack {
                    GoalPaceTrendChart(
                        values: series,
                        goalValue: goal,
                        color: accent,
                        progress: appeared || reduceMotion ? 1 : 0,
                        width: geo.size.width,
                        height: 92
                    )
                }
            }
            .frame(height: 92)

            HStack(spacing: Theme.Spacing.md) {
                legendItem(color: accent, label: "Weight trend")
                if showGoalLine {
                    legendItem(color: Theme.Colors.labelTertiary, label: "Goal \(GoalPaceState.lb(state.targetWeightLb))", dashed: true)
                }
                Spacer(minLength: 0)
                Txt("last \(series.count) days", variant: .footnote, color: .labelTertiary)
            }
        }
        .onAppear {
            guard !reduceMotion else { appeared = true; return }
            withAnimation(.easeOut(duration: 0.6)) { appeared = true }
        }
    }

    private func legendItem(color: Color, label: String, dashed: Bool = false) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Capsule()
                .fill(dashed ? color.opacity(0.55) : color)
                .frame(width: 14, height: dashed ? 2 : 3)
            Txt(label, variant: .footnote, color: .labelTertiary)
        }
    }
}

/// Smooth EWMA trend line (lb) with a soft area fill and a dashed horizontal goal line. Canvas
/// drawing on shared `LineGeometry`/`ChartCurve` math; the goal value is folded into the y-bounds so
/// the goal line always sits on the plot. `progress` (0…1) trims the line for the appear animation
/// (pass 1 under Reduce Motion). Display-only.
private struct GoalPaceTrendChart: View, Animatable {
    let values: [Double]
    var goalValue: Double?
    var color: Color = Theme.Chart.sleep
    var progress: Double = 1
    var width: CGFloat = 200
    var height: CGFloat = 92

    /// Bridges `progress` into SwiftUI's animation system; Canvas content isn't implicitly
    /// animatable, so without this the trim would snap 0→1 in one frame instead of drawing in.
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { ctx, _ in
            guard values.count > 1 else { return }
            let vPadding: CGFloat = 8
            let coords = LineGeometry.lineCoords(values, width: width, height: height, vPadding: vPadding, extra: goalValue)
            let line = ChartCurve.smoothLine(coords)

            if let f = coords.first, let l = coords.last {
                var area = line
                area.addLine(to: CGPoint(x: l.x, y: height))
                area.addLine(to: CGPoint(x: f.x, y: height))
                area.closeSubpath()
                ctx.fill(area, with: .linearGradient(
                    Gradient(colors: [color.opacity(0.20), color.opacity(0.0)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: height)))
            }

            if let goalValue {
                let bounds = LineGeometry.valueBounds(values, extra: goalValue)
                let gy = LineGeometry.valueToY(goalValue, min: bounds.min, max: bounds.max, height: height, vPadding: vPadding)
                var goalLine = Path()
                goalLine.move(to: CGPoint(x: 0, y: gy))
                goalLine.addLine(to: CGPoint(x: width, y: gy))
                ctx.stroke(goalLine, with: .color(Theme.Colors.labelTertiary.opacity(0.7)),
                           style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            }

            let trimmed = line.trimmedPath(from: 0, to: progress)
            ctx.stroke(trimmed, with: .color(color),
                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

            if progress >= 0.999, let last = coords.last {
                let r: CGFloat = 3.5
                ctx.fill(Path(ellipseIn: CGRect(x: last.x - r, y: last.y - r, width: r * 2, height: r * 2)),
                         with: .color(color))
            }
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Goal pace states") {
    ScrollView {
        VStack(spacing: Theme.Spacing.lg) {
            if let onTrack = GoalPaceState.evaluate(
                weightHistoryLb: SampleData.weightHistoryLb,
                lastWeighInKey: DateStrip.toKey(SampleData.referenceDate),
                targetWeightLb: SampleData.goalTargetWeightLb,
                targetDateKey: SampleData.goalTargetDateKey,
                today: SampleData.referenceDate
            ) {
                GoalPaceCard(state: onTrack)
            }
        }
        .padding(Theme.Spacing.lg)
    }
    .background(Theme.Colors.background)
}
#endif
