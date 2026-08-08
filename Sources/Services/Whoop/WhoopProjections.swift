import Foundation

enum WhoopProjections {
    /// Whoop's logarithmic strain scale is 0–21.
    private static let strainMax = 21.0

    /// Parse "78", "42 bpm", "1,792" → number; nil for time labels or junk.
    static func parseStatNumber(_ s: String?) -> Double? {
        guard let s else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        if WhoopWalk.timeLabelToMs(trimmed) != nil { return nil }
        let kept = s.unicodeScalars.filter { scalar in
            let c = Character(scalar)
            if c == "," || c == "%" || c == "°" { return false }
            if c.isLetter { return false }
            return true
        }
        let cleaned = String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespaces)
        guard let n = Double(cleaned), n.isFinite else { return nil }
        return n
    }

    /// Map the gauge fill style to a recovery zone.
    private static func stateFromStyle(_ style: String?) -> WhoopRecoveryState? {
        switch style {
        case "RECOVERY_HIGH": return .green
        case "RECOVERY_MEDIUM": return .yellow
        case "RECOVERY_LOW": return .red
        default: return nil
        }
    }

    /// A tile of `type` whose content.id equals `id`.
    private static func findTileById(
        _ tiles: [WhoopWalk.Tile], _ type: String, _ id: String
    ) -> WhoopWalk.Tile? {
        tiles.first { $0.type == type && $0.content["id"].stringValue == id }
    }

    /// A CONTRIBUTORS_TILE metric whose `id` ends with `idSuffix` (case-insensitive).
    private static func findContributor(_ metrics: [JSONValue], _ idSuffix: String) -> JSONValue? {
        let upper = idSuffix.uppercased()
        return metrics.first { $0["id"].stringValue?.uppercased().hasSuffix(upper) ?? false }
    }

    /// A contributor's today value + baseline ("status" / "status_subtitle").
    private static func readContributor(
        _ metrics: [JSONValue], _ idSuffix: String
    ) -> (current: Double?, baseline: Double?) {
        guard let m = findContributor(metrics, idSuffix) else { return (nil, nil) }
        return (parseStatNumber(m["status"].stringValue),
                parseStatNumber(m["status_subtitle"].stringValue))
    }

    /// The physiological day's start as an ISO timestamp from the /home payload's
    /// `metadata.cycle_metadata.during.lower_endpoint`. nil when absent/malformed.
    private static func homeRecordedAt(_ home: JSONValue) -> String? {
        home["metadata"]["cycle_metadata"]["during"]["lower_endpoint"].stringValue
    }

    /// Today's energy burned (kcal) from `metadata.whoop_live_metadata.calories`,
    /// rounded to an integer. nil when absent/non-numeric.
    private static func homeCalories(_ home: JSONValue) -> Double? {
        guard let kcal = home["metadata"]["whoop_live_metadata"]["calories"].numberValue
        else { return nil }
        return kcal.rounded()
    }

    /// Daily steps + 30-day baseline from the /home payload's STEPS KEY_STATISTIC
    /// (`current_value_display` "5,322" / `thirty_day_value_display` "6,363", commas
    /// stripped by `numberValue`). nil when absent or non-numeric.
    private static func homeSteps(_ home: JSONValue) -> WhoopSteps? {
        let tile = WhoopWalk.findFirst(home) { n in
            n["type"].stringValue == "KEY_STATISTIC"
                && n["content"]["trend_key"].stringValue == "STEPS"
        }
        guard let content = tile?["content"],
              let count = content["current_value_display"].numberValue
        else { return nil }
        let baseline = content["thirty_day_value_display"].numberValue
        return WhoopSteps(
            count: Int(count.rounded()),
            baseline30d: baseline.map { Int($0.rounded()) }
        )
    }

    /// A SCORE_GAUGE_STICKY gauge by its pillar title (RECOVERY / SLEEP / STRAIN).
    private static func stickyGauge(_ home: JSONValue, _ title: String) -> JSONValue? {
        guard let sticky = WhoopWalk.findByType(home, "SCORE_GAUGE_STICKY") else { return nil }
        return sticky["content"]["gauges"].arrayValue.first { $0["title"].stringValue == title }
    }

    /// Project `/developer/v2/user/measurement/body` into the body measurement.
    ///
    /// Returns nil unless a positive weight is present. That guard is the important part: a WHOOP
    /// account with nothing stored — and the secondary account behind `custom:account_id` — answers
    /// `weight_kilogram: 0.0`, and adopting that would write a 0 lb weigh-in, flatten the trend and
    /// feed 0 into the BMR/goal maths. Height and max HR are optional and dropped when non-positive.
    static func projectBodyMeasurement(_ raw: JSONValue) -> WhoopBodyMeasurement? {
        guard let kg = raw["weight_kilogram"].numberValue, kg > 0 else { return nil }
        return WhoopBodyMeasurement(
            weightKg: kg,
            heightMeters: raw["height_meter"].numberValue.flatMap { $0 > 0 ? $0 : nil },
            maxHeartRate: raw["max_heart_rate"].numberValue.flatMap { $0 > 0 ? Int($0) : nil }
        )
    }

    /// Project the /home aggregate into the dashboard summary. The sticky gauges carry the three
    /// pillar scores + the recovery fill style; the contributors/vitals come from whatever
    /// CONTRIBUTORS_TILE the home payload also inlines (Whoop has been migrating these into /home),
    /// each looked up defensively.
    static func projectHomeSummary(_ home: JSONValue) -> WhoopSummary {
        let tiles = WhoopWalk.collectTiles(home)

        let recoveryGauge = stickyGauge(home, "RECOVERY")
        let sleepGauge = stickyGauge(home, "SLEEP")
        let strainGauge = stickyGauge(home, "STRAIN")

        let recoveryPct = recoveryGauge?["score_display"].numberValue
        let recoveryState = stateFromStyle(recoveryGauge?["progress_fill_style"].stringValue)
        let sleepPerformancePct = sleepGauge?["score_display"].numberValue
        let dayStrain = strainGauge?["score_display"].numberValue

        let recContrib = findTileById(tiles, "CONTRIBUTORS_TILE", "RECOVERY_CONTRIBUTORS_TILE")
        let recMetrics = recContrib?.content["metrics"].arrayValue ?? []
        let hrv = readContributor(recMetrics, "HRV")
        let rhr = readContributor(recMetrics, "RHR")
        let respiratory = readContributor(recMetrics, "RESPIRATORY_RATE")
        let spo2 = readContributor(recMetrics, "SPO2")
        let skinTemp = readContributor(recMetrics, "SKIN_TEMPERATURE")

        var summary = WhoopSummary(
            recoveryPct: recoveryPct,
            recoveryState: recoveryState,
            hrvMs: hrv.current,
            hrvBaselineMs: hrv.baseline,
            rhrBpm: rhr.current,
            rhrBaselineBpm: rhr.baseline,
            respiratoryRate: respiratory.current,
            spo2Pct: spo2.current,
            skinTempC: skinTemp.current.map { ($0 * 10).rounded() / 10 },
            sleepPerformancePct: sleepPerformancePct,
            sleepHours: nil,
            dayStrain: dayStrain,
            calories: homeCalories(home),
            steps: homeSteps(home),
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            recordedAt: homeRecordedAt(home)
        )

        if let card = WhoopWalk.findDetailsCardByTitle(home, "HOURS OF SLEEP"),
           let sleepMs = WhoopWalk.timeLabelToMs(arrowStat(card)) {
            summary.sleepHours = (sleepMs / 3_600_000 * 100).rounded() / 100
        }

        return summary
    }

    /// Detailed recovery: score + state + HRV/RHR (value + baseline + Δ%) + vitals.
    /// File-local (never crosses the module boundary): the Whoop tab reads the merged
    /// contributors off `WhoopSummary`.
    struct RecoveryDetail: Sendable, Equatable {
        let date: String
        let score: Double?
        let state: WhoopRecoveryState?
        let hrvMs: Double?
        let hrvBaselineMs: Double?
        let hrvDeltaPct: Double?
        let rhrBpm: Double?
        let rhrBaselineBpm: Double?
        let rhrDeltaPct: Double?
        let respiratoryRate: Double?
        let spo2Pct: Double?
        let skinTempC: Double?
        let sleepPerformancePct: Double?
    }

    /// Percent change current vs baseline, 1-decimal; nil on a missing/zero baseline.
    private static func deltaPct(_ current: Double?, _ baseline: Double?) -> Double? {
        guard let current, let baseline, baseline != 0 else { return nil }
        return ((current - baseline) / baseline * 1000).rounded() / 10
    }

    /// Walk SCORE_GAUGE + CONTRIBUTORS_TILE items.
    static func projectRecoveryDetail(_ raw: JSONValue, date: String) -> RecoveryDetail {
        let tiles = WhoopWalk.collectTiles(raw)

        let gauge = findTileById(tiles, "SCORE_GAUGE", "RECOVERY_SCORE_GAUGE")
        let score = parseStatNumber(gauge?.content["score_display"].stringValue)
        let state = stateFromStyle(gauge?.content["progress_fill_style"].stringValue)

        let contributors = findTileById(tiles, "CONTRIBUTORS_TILE", "RECOVERY_CONTRIBUTORS_TILE")
        let metrics = contributors?.content["metrics"].arrayValue ?? []
        let hrv = readContributor(metrics, "HRV")
        let rhr = readContributor(metrics, "RHR")
        let respiratory = readContributor(metrics, "RESPIRATORY_RATE")
        let sleepPerf = readContributor(metrics, "SLEEP_PERFORMANCE")
        let spo2 = readContributor(metrics, "SPO2")
        let skinTemp = readContributor(metrics, "SKIN_TEMPERATURE")

        return RecoveryDetail(
            date: date,
            score: score,
            state: state,
            hrvMs: hrv.current,
            hrvBaselineMs: hrv.baseline,
            hrvDeltaPct: deltaPct(hrv.current, hrv.baseline),
            rhrBpm: rhr.current,
            rhrBaselineBpm: rhr.baseline,
            rhrDeltaPct: deltaPct(rhr.current, rhr.baseline),
            respiratoryRate: respiratory.current,
            spo2Pct: spo2.current,
            skinTempC: skinTemp.current.map { ($0 * 10).rounded() / 10 },
            sleepPerformancePct: sleepPerf.current
        )
    }

    /// Merge a recovery deep-dive into a /home summary. The /home gauges carry the recovery score
    /// + fill state but not the underlying HRV/RHR/respiratory/sleep-performance contributors;
    /// those live only in /deep-dive/recovery. Overlays the detail's contributor values onto the
    /// summary without clobbering what the summary already has, and returns a new value (does not
    /// mutate). Every overlay is nil-guarded.
    static func mergeRecoveryDetail(_ summary: WhoopSummary, _ detail: RecoveryDetail?) -> WhoopSummary {
        guard let detail else { return summary }
        var merged = summary
        if let v = detail.score { merged.recoveryPct = v }
        if let v = detail.state { merged.recoveryState = v }
        if let v = detail.hrvMs { merged.hrvMs = v }
        if let v = detail.hrvBaselineMs { merged.hrvBaselineMs = v }
        if let v = detail.rhrBpm { merged.rhrBpm = v }
        if let v = detail.rhrBaselineBpm { merged.rhrBaselineBpm = v }
        if let v = detail.respiratoryRate { merged.respiratoryRate = v }
        if let v = detail.spo2Pct { merged.spo2Pct = v }
        if let v = detail.skinTempC { merged.skinTempC = v }
        if let v = detail.sleepPerformancePct { merged.sleepPerformancePct = v }
        return merged
    }

    /// First arrow_stat.current_stat_text on a DETAILS_GRAPHING_CARD ("7:24", "85%").
    private static func arrowStat(_ card: JSONValue?) -> String? {
        guard let card else { return nil }
        return card["content"]["arrow_stat"].arrayValue.first?["current_stat_text"].stringValue
    }

    /// First arrow_stat.historic_stat_text on a DETAILS_GRAPHING_CARD (the 30-day baseline).
    private static func arrowStatHistoric(_ card: JSONValue?) -> String? {
        guard let card else { return nil }
        return card["content"]["arrow_stat"].arrayValue.first?["historic_stat_text"].stringValue
    }

    /// The SLEEP NEEDED bar's value_display from the HOURS VS. NEEDED card ("8:24").
    private static func sleepNeededDisplay(_ raw: JSONValue) -> String? {
        let bar = WhoopWalk.findFirst(raw) { $0["title_display"].stringValue == "SLEEP NEEDED" }
        return bar?["value_display"].stringValue
    }

    /// The sleep "stages" BAR_GRAPH_CARD's content, not the stress card: a non-empty
    /// `duration_display` marks the stages card (the stress card is "").
    private static func sleepStagesCard(_ raw: JSONValue) -> JSONValue? {
        WhoopWalk.findFirst(raw) { n in
            guard n["type"].stringValue == "BAR_GRAPH_CARD" else { return false }
            let dur = n["content"]["duration_display"].stringValue
            return (dur?.isEmpty == false)
        }
    }

    /// The stage bars keyed by stage id (AWAKE / LIGHT_SLEEP / SWS_SLEEP / REM_SLEEP).
    private static func stageBarsById(_ content: JSONValue) -> [String: JSONValue] {
        var byId: [String: JSONValue] = [:]
        for z in content["heart_rate_zones"].arrayValue {
            if let id = z["id"].stringValue { byId[id] = z }
        }
        return byId
    }

    /// A single stage's duration (ms) + share (%) from the stage-bar map.
    private static func stage(
        _ bars: [String: JSONValue], _ stageId: String
    ) -> (ms: Double?, pct: Double?) {
        guard let bar = bars[stageId], bar.isObject else { return (nil, nil) }
        return (WhoopWalk.timeLabelToMs(bar["bar_graph_tile_time_display"].stringValue),
                WhoopWalk.labelToNumber(bar["bar_graph_tile_percentage_display"].stringValue))
    }

    /// A stage's "typical range" band (fractions 0–1 of total sleep), from the stage bar's
    /// `bar_graph.graph_range_endpoints`. nil unless both endpoints are finite.
    private static func stageRange(_ bars: [String: JSONValue], _ stageId: String) -> SleepStageRange? {
        guard let bar = bars[stageId], bar.isObject else { return nil }
        let ep = bar["bar_graph"]["graph_range_endpoints"]
        guard let lower = ep["lower_endpoint"].numberValue,
              let upper = ep["upper_endpoint"].numberValue
        else { return nil }
        return SleepStageRange(lower: lower, upper: upper)
    }

    /// A DETAILS_METRIC_TILES tile's value by its title, read from arrow_stat
    /// (`content.arrow_stat[0].current_stat_text`).
    private static func metricTileStat(_ raw: JSONValue, _ title: String) -> String? {
        let tile = WhoopWalk.findFirst(raw) { n in
            n["type"].stringValue == "DETAILS_METRIC_TILES" && n["content"]["title"].stringValue == title
        }
        return arrowStat(tile)
    }

    /// The `plots` container holding a LINE_PLOT whose `plot.id` equals `plotId`.
    /// Located by the plot id so a reordered payload still resolves.
    private static func plotsContainerByPlotId(_ raw: JSONValue, _ plotId: String) -> JSONValue? {
        WhoopWalk.findFirst(raw) { n in
            guard case .array = n["plots"] else { return false }
            return n["plots"].arrayValue.contains { $0["plot"]["id"].stringValue == plotId }
        }
    }

    /// Every object `points[]` entry across one plot's `segments[]`.
    private static func segmentPoints(_ plot: JSONValue) -> [JSONValue] {
        var out: [JSONValue] = []
        for seg in plot["segments"].arrayValue {
            for pt in seg["points"].arrayValue where pt.isObject { out.append(pt) }
        }
        return out
    }

    /// Every `segments[].points[]` entry across all plots in a `plots[]` container.
    private static func eachPlotPoint(_ container: JSONValue) -> [JSONValue] {
        var out: [JSONValue] = []
        for p in container["plots"].arrayValue where p["plot"].isObject {
            out.append(contentsOf: segmentPoints(p["plot"]))
        }
        return out
    }

    /// One overnight HR point ({x, bpm, clock}) from its scrubber details, or nil. The bpm is a
    /// string in value_display (numeric `value` is null), so parse the string.
    private static func hrPoint(_ pt: JSONValue) -> SleepHrPoint? {
        let dsd = pt["data_scrubber_details"]
        guard dsd.isObject,
              let bpmStr = dsd["value_display"].stringValue,
              let bpm = Int(bpmStr).map(Double.init) ?? Double(bpmStr),
              let clock = dsd["secondary_contextual_display"].stringValue,
              let x = pt["position_x"].numberValue
        else { return nil }
        return SleepHrPoint(x: x, bpm: bpm, clock: clock)
    }

    /// Merge the five overnight heart-rate line-plots into one curve, sorted by `x`. Points with
    /// `data_scrubber_details: null` (render-only spline filler carrying no bpm/clock) are dropped,
    /// never zero-/back-filled. nil when no real readings exist.
    private static func sleepHrCurve(_ raw: JSONValue) -> [SleepHrPoint]? {
        guard let container = plotsContainerByPlotId(raw, "SLEEP_HEART_RATE") else { return nil }
        var out: [SleepHrPoint] = []
        for pt in eachPlotPoint(container) {
            if let point = hrPoint(pt) { out.append(point) }
        }
        guard !out.isEmpty else { return nil }
        out.sort { $0.x < $1.x }
        return out
    }

    /// One overnight stress point ({x, level, clock, band}) from its details, or nil.
    private static func sleepStressPoint(_ pt: JSONValue) -> SleepStressPoint? {
        let dsd = pt["data_scrubber_details"]
        guard let level = dsd["value_display"].numberValue,
              let x = pt["position_x"].numberValue,
              let clock = dsd["primary_contextual_display"].stringValue,
              let band = dsd["secondary_contextual_display"].stringValue
        else { return nil }
        return SleepStressPoint(x: x, level: level, clock: clock, band: band)
    }

    /// The overnight sleep-stress curve (id "stress"), oldest → newest by `x`. Points
    /// missing a finite level / clock / band are dropped. nil when none exist.
    private static func sleepStressCurve(_ raw: JSONValue) -> [SleepStressPoint]? {
        guard let container = plotsContainerByPlotId(raw, "stress"),
              let plot = container["plots"].arrayValue.first(where: { $0["plot"]["id"].stringValue == "stress" }),
              plot["plot"].isObject
        else { return nil }
        var out: [SleepStressPoint] = []
        for pt in segmentPoints(plot["plot"]) {
            if let point = sleepStressPoint(pt) { out.append(point) }
        }
        guard !out.isEmpty else { return nil }
        out.sort { $0.x < $1.x }
        return out
    }

    /// The SLEEP-STRESS breakdown BAR_GRAPH_CARD (empty `duration_display`, ids end in `_STRESS`).
    private static func sleepStressBreakdownCard(_ raw: JSONValue) -> JSONValue? {
        WhoopWalk.findFirst(raw) { n in
            guard n["type"].stringValue == "BAR_GRAPH_CARD" else { return false }
            guard n["content"]["duration_display"].stringValue == "" else { return false }
            return n["content"]["heart_rate_zones"].arrayValue.contains {
                ($0["id"].stringValue ?? "").hasSuffix("_STRESS")
            }
        }
    }

    /// One stress band's {pctDisplay, timeDisplay} from the breakdown bar map, or nil.
    private static func stressBand(_ bars: [String: JSONValue], _ bandId: String) -> SleepStressBand? {
        guard let bar = bars[bandId], bar.isObject,
              let pctDisplay = bar["bar_graph_tile_percentage_display"].stringValue,
              let timeDisplay = bar["bar_graph_tile_time_display"].stringValue
        else { return nil }
        return SleepStressBand(pctDisplay: pctDisplay, timeDisplay: timeDisplay)
    }

    /// Assemble the overnight SleepStress object: headline % (SLEEP STRESS card), the 0–3 curve,
    /// and the HIGH/MEDIUM/LOW breakdown. nil only when none of the three is present. Every
    /// sub-part is independently nil-guarded.
    private static func projectSleepStress(_ raw: JSONValue) -> SleepStress? {
        let overallPct = WhoopWalk.labelToNumber(arrowStat(WhoopWalk.findDetailsCardByTitle(raw, "SLEEP STRESS")))
        let curve = sleepStressCurve(raw)

        let breakdownContent = sleepStressBreakdownCard(raw)?["content"] ?? .null
        let bandBars = stageBarsById(breakdownContent)
        let high = stressBand(bandBars, "HIGH_STRESS")
        let medium = stressBand(bandBars, "MEDIUM_STRESS")
        let low = stressBand(bandBars, "LOW_STRESS")
        let breakdown: SleepStressBreakdown? = (high != nil || medium != nil || low != nil)
            ? SleepStressBreakdown(high: high, medium: medium, low: low)
            : nil

        if overallPct == nil, curve == nil, breakdown == nil { return nil }
        return SleepStress(overallPct: overallPct, curve: curve, breakdown: breakdown)
    }

    /// Project /deep-dive/sleep/last-night → SleepDetail.
    static func projectSleepDetail(_ raw: JSONValue, date: String) -> SleepDetail {
        let params = raw["header_section"]["destination"]["parameters"]
        let startTime = params["start_time"].stringValue
        let endTime = params["end_time"].stringValue

        let stagesContent = sleepStagesCard(raw)?["content"] ?? .null
        let timeInBedMs = WhoopWalk.timeLabelToMs(stagesContent["duration_display"].stringValue)
        let bars = stageBarsById(stagesContent)

        let rem = stage(bars, "REM_SLEEP")
        let light = stage(bars, "LIGHT_SLEEP")
        let sws = stage(bars, "SWS_SLEEP")
        let wake = stage(bars, "AWAKE")

        let hoursCard = WhoopWalk.findDetailsCardByTitle(raw, "HOURS OF SLEEP")
        let restorativeText = metricTileStat(raw, "RESTORATIVE SLEEP")
        let latencyText = metricTileStat(raw, "SLEEP LATENCY")
        let durationInBed = stagesContent["duration_display"].stringValue
        let wakeEvents = WhoopWalk.labelToNumber(metricTileStat(raw, "WAKE EVENTS"))

        let stages = SleepStages(
            remMs: rem.ms, lightMs: light.ms, swsMs: sws.ms, wakeMs: wake.ms,
            remPct: rem.pct, lightPct: light.pct, swsPct: sws.pct, wakePct: wake.pct,
            remRange: stageRange(bars, "REM_SLEEP"),
            lightRange: stageRange(bars, "LIGHT_SLEEP"),
            swsRange: stageRange(bars, "SWS_SLEEP"),
            wakeRange: stageRange(bars, "AWAKE")
        )

        return SleepDetail(
            date: date,
            startedAt: startTime,
            endedAt: endTime,
            totalSleepMs: WhoopWalk.timeLabelToMs(arrowStat(WhoopWalk.findDetailsCardByTitle(raw, "HOURS OF SLEEP"))),
            timeInBedMs: timeInBedMs,
            performancePct: WhoopWalk.labelToNumber(arrowStat(WhoopWalk.findDetailsCardByTitle(raw, "HOURS VS"))),
            consistencyPct: WhoopWalk.labelToNumber(arrowStat(WhoopWalk.findDetailsCardByTitle(raw, "SLEEP CONSISTENCY"))),
            efficiencyPct: WhoopWalk.labelToNumber(arrowStat(WhoopWalk.findDetailsCardByTitle(raw, "SLEEP EFFICIENCY"))),
            latencyMs: WhoopWalk.timeLabelToMs(latencyText),
            restorativeMs: WhoopWalk.timeLabelToMs(restorativeText),
            respiratoryRate: nil,
            stages: stages,
            disturbances: wakeEvents,
            hours: arrowStat(hoursCard),
            hoursBaseline: arrowStatHistoric(hoursCard),
            hoursNeeded: sleepNeededDisplay(raw),
            durationInBed: durationInBed,
            restorative: restorativeText,
            latency: latencyText,
            wakeEvents: wakeEvents,
            performancePctExt: WhoopWalk.labelToNumber(arrowStat(WhoopWalk.findDetailsCardByTitle(raw, "HOURS VS"))),
            efficiencyPctExt: WhoopWalk.labelToNumber(arrowStat(WhoopWalk.findDetailsCardByTitle(raw, "SLEEP EFFICIENCY"))),
            consistencyPctExt: WhoopWalk.labelToNumber(arrowStat(WhoopWalk.findDetailsCardByTitle(raw, "SLEEP CONSISTENCY"))),
            hrCurve: sleepHrCurve(raw),
            windowStart: startTime,
            windowEnd: endTime,
            sleepStress: projectSleepStress(raw)
        )
    }

    /// A strain target fraction (0–1) × `strainMax`, or nil when non-numeric.
    /// Only a real JSON number counts, not a numeric string.
    private static func targetFraction(_ content: JSONValue, _ key: String) -> Double? {
        guard case let .number(v) = content[key], v.isFinite else { return nil }
        return v * strainMax
    }

    /// Parse "2:35" → ms; also "2:35:12" (h:m:s).
    private static func clockToMs(_ s: String?) -> Double? {
        guard let s else { return nil }
        let parts = s.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        let nums = parts.map { Double($0) }
        guard !nums.contains(where: { $0 == nil }) else { return nil }
        let vals = nums.compactMap { $0 }
        if vals.count == 2 { return (vals[0] * 60 + vals[1]) * 60 * 1000 }
        if vals.count == 3 { return (vals[0] * 3600 + vals[1] * 60 + vals[2]) * 1000 }
        return nil
    }

    /// Project /home-service/v1/deep-dive/strain → StrainDetail.
    static func projectStrainDetail(_ raw: JSONValue, date: String) -> StrainDetail {
        let tiles = WhoopWalk.collectTiles(raw)

        let gauge = findTileById(tiles, "SCORE_GAUGE", "STRAIN_SCORE_GAUGE")
        let score = parseStatNumber(gauge?.content["score_display"].stringValue)
        let target = StrainTarget(
            value: gauge.flatMap { targetFraction($0.content, "score_target") },
            optimalLower: gauge.flatMap { targetFraction($0.content, "lower_optimal_percentage") },
            optimalUpper: gauge.flatMap { targetFraction($0.content, "higher_optimal_percentage") }
        )

        let contributors = findTileById(tiles, "CONTRIBUTORS_TILE", "STRAIN_CONTRIBUTORS_TILE")
        let metrics = contributors?.content["metrics"].arrayValue ?? []
        func readTime(_ suffix: String) -> Double? {
            clockToMs(findContributor(metrics, suffix)?["status"].stringValue)
        }
        func readTimeBaseline(_ suffix: String) -> Double? {
            clockToMs(findContributor(metrics, suffix)?["status_subtitle"].stringValue)
        }
        func readNum(_ suffix: String) -> Double? {
            parseStatNumber(findContributor(metrics, suffix)?["status"].stringValue)
        }
        func readNumBaseline(_ suffix: String) -> Double? {
            parseStatNumber(findContributor(metrics, suffix)?["status_subtitle"].stringValue)
        }

        return StrainDetail(
            date: date,
            score: score,
            target: target,
            zone13Ms: readTime("HR_ZONES_1_3"),
            zone13BaselineMs: readTimeBaseline("HR_ZONES_1_3"),
            zone45Ms: readTime("HR_ZONES_4_5"),
            zone45BaselineMs: readTimeBaseline("HR_ZONES_4_5"),
            strengthActivityMs: readTime("STRENGTH_TRAINING_TIME"),
            strengthActivityBaselineMs: readTimeBaseline("STRENGTH_TRAINING_TIME"),
            steps: readNum("STEPS"),
            stepsBaseline: readNumBaseline("STEPS"),
            kilojoules: nil,
            calories: nil,
            workoutsCount: tiles.filter { $0.type == "ACTIVITY" }.count
        )
    }

    /// Cap on emitted curve points; the raw graph holds ~700 intraday samples.
    private static let stressMaxGraphPoints = 48

    /// Evenly downsample `arr` to at most `max`, always keeping the final element.
    private static func downsample<T: Equatable>(_ arr: [T], _ max: Int) -> [T] {
        guard arr.count > max else { return arr }
        let step = Double(arr.count) / Double(max)
        var out: [T] = []
        for i in 0..<max { out.append(arr[Int((Double(i) * step).rounded(.down))]) }
        if let last = arr.last, out.last != last { out.append(last) }
        return out
    }

    /// One point's { time, value } from its data_scrubber_details, or nil if incomplete.
    private static func stressPoint(_ pt: JSONValue) -> StressGraphPoint? {
        guard pt.isObject else { return nil }
        let dsd = pt["data_scrubber_details"]
        guard let time = dsd["primary_contextual_display"].stringValue,
              let value = WhoopWalk.labelToNumber(dsd["value_display"].stringValue)
        else { return nil }
        return StressGraphPoint(time: time, value: value)
    }

    /// Walk stress_graph.graph.plots[].plot.segments[].points[] into ordered
    /// { time, value } pairs. Points missing a clock label or a numeric level are dropped.
    private static func collectStressPoints(_ graph: JSONValue) -> [StressGraphPoint] {
        var out: [StressGraphPoint] = []
        for p in graph["plots"].arrayValue where p["plot"].isObject {
            for seg in p["plot"]["segments"].arrayValue {
                for pt in seg["points"].arrayValue {
                    if let point = stressPoint(pt) { out.append(point) }
                }
            }
        }
        return out
    }

    /// Project /health-service/v2/stress-bff/<date> → StressDetail. The headline gauge
    /// gives the current level; the line-chart points give the day curve + min/max.
    /// `currentStress` falls back to the last graphed sample when the gauge is absent.
    /// While calibrating, `stressState` reports "CALIBRATING".
    static func projectStressDetail(_ raw: JSONValue, date: String) -> StressDetail {
        let gauge = raw["gauge"]
        let points = collectStressPoints(raw["stress_graph"]["graph"])
        let sampled = downsample(points, stressMaxGraphPoints)
        let levels = points.map { $0.value }

        let gaugeLevel = WhoopWalk.labelToNumber(gauge["gauge_score_display"].stringValue)
        let currentStress = gaugeLevel ?? levels.last

        let calibrating = raw["calibration_text_display"].stringValue != nil
            || raw["stress_state"].stringValue == "CALIBRATING"
        let stressState = calibrating ? "CALIBRATING" : raw["stress_state"].stringValue

        return StressDetail(
            date: date,
            currentStress: currentStress,
            stressState: stressState,
            minStress: levels.min(),
            maxStress: levels.max(),
            lastUpdated: raw["last_updated_display"].stringValue,
            graph: sampled,
            trend: raw["trend"].stringValue
        )
    }
}
