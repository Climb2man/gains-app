import Foundation

/// Login outcome surfaced to the connect UI.
enum WhoopLoginResult: Sendable, Equatable {
    case ok
    case mfa(WhoopMfaHandle)
    case failed
}

/// Opaque handle the UI carries from login back into submitMfa.
struct WhoopMfaHandle: Sendable, Equatable {
    let challenge: WhoopMfaChallenge
    let session: String
    let username: String
}

/// A metric exposed as a dated trend series.
enum WhoopHistoryMetric: String, Sendable, Equatable {
    case recovery, hrv, rhr, strain
}

/// One dated point in a trend series. `value` is nil when that day has no data.
struct WhoopHistoryPoint: Sendable, Equatable {
    let date: String
    let value: Double?
}

/// The Whoop data surface the UI depends on. Behind a protocol so the client is swappable for a
/// mock in tests and previews.
protocol WhoopService: Sendable {
    func login(email: String, password: String) async -> WhoopLoginResult
    func submitMfa(code: String, handle: WhoopMfaHandle) async -> Bool
    func clear() async
    func isLinked() async -> Bool

    /// The dashboard snapshot for `date` (default today), /home merged with /deep-dive/
    /// recovery (+ a sleep-hours fallback). 15-min cache, in-flight de-dup, backoff.
    func summary(date: String?, force: Bool) async -> WhoopSummary?
    func sleepDetail(date: String?) async -> SleepDetail?
    func strainDetail(date: String?) async -> StrainDetail?
    func stressDetail(date: String?, force: Bool) async -> StressDetail?
    /// Dated points for one metric over the last `days` days (oldest → newest, clamped
    /// 1…366). Cached days are free; at most 14 uncached days hit the network per call, so
    /// long windows (the 126-day recovery calendar) backfill progressively across calls.
    func history(metric: WhoopHistoryMetric, days: Int) async -> [WhoopHistoryPoint]

    /// The current heart rate from the strap (the `/health-tab-bff` LIVE_HR tile). nil when
    /// unlinked or the tile is absent. Not cached: a live value the caller polls.
    func liveHeartRate() async -> WhoopLiveHr?

    /// WHOOP's own behavior→outcome impacts ("Alcohol · −12%"). Restated verbatim; empty when
    /// unlinked or none computed. 15-min in-session cache (it changes slowly).
    func behaviorImpacts() async -> [WhoopBehaviorImpact]

    /// WHOOP's sleep-need coaching for the night. nil when unlinked / not yet computed.
    func sleepNeed() async -> WhoopSleepNeed?

    /// WHOOP's stored weight/height/max-HR. nil when unlinked or WHOOP holds no weight.
    /// This is the app's weight source: a smart scale pushing to WHOOP lands here.
    /// `force: true` skips the cache — for the manual Sync button, whose whole purpose is to go and
    /// look now. Automatic callers pass false and share the 15-minute cache.
    func bodyMeasurement(force: Bool) async -> WhoopBodyMeasurement?

    /// WHOOP's age/sex/weight/height, so the Gains profile needs no manual entry. nil when
    /// unlinked or when the user id cannot be read from the token.
    func userProfile() async -> WhoopUserProfile?
}

/// The orchestrating client. An `actor`: the per-day cache state, in-flight de-dup, and
/// backoff cooldowns must be serialized on a single executor.
actor WhoopClient: WhoopService {
    private static let homePath = "/home-service/v1/home"
    private static let recoveryDeepDivePath = "/home-service/v1/deep-dive/recovery"
    private static let sleepDeepDivePath = "/home-service/v1/deep-dive/sleep/last-night"
    private static let strainDeepDivePath = "/home-service/v1/deep-dive/strain"
    private static let stressBffPrefix = "/health-service/v2/stress-bff/"
    /// WHOOP's official-API body-measurement path, served to the app token. Not user-scoped.
    private static let bodyMeasurementPath = "/developer/v2/user/measurement/body"
    /// Body measurement changes at most a few times a day (a scale push), so 15 min is generous.
    private static let bodyMeasurementTtlMs: Double = 15 * 60 * 1000

    private struct BodyMeasurementCacheEntry {
        let fetchedAt: Double
        let value: WhoopBodyMeasurement
    }

    /// In-session only: deliberately NOT persisted. WHOOP stays the source of truth, and the
    /// weigh-in that gets logged from it is already durable in WeightStore.
    private var bodyMeasurementCache: BodyMeasurementCacheEntry?

    /// Age and sex change on the order of years, so this can be cached hard.
    private static let userProfileTtlMs: Double = 24 * 60 * 60 * 1000

    private struct UserProfileCacheEntry {
        let fetchedAt: Double
        let value: WhoopUserProfile
    }

    private var userProfileCache: UserProfileCacheEntry?

    /// Stress monitor path: the date is a path segment here, not a `?date=` query.
    private static func stressPath(_ date: String) -> String {
        let encoded = date.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? date
        return stressBffPrefix + encoded
    }

    private static let summaryCachePrefix = "@gains/whoop/summary-cache/"
    private static let historyCachePrefix = "@gains/whoop/history-cache/"
    private static let stressCachePrefix = "@gains/whoop/stress-cache/"
    private static let cacheTtlMs: Double = 15 * 60 * 1000
    private static let historyPastTtlMs: Double = 7 * 24 * 60 * 60 * 1000
    /// Network budget per `history` call: at most this many uncached days go to the API.
    private static let historyNetworkBudgetDays = 14
    /// Hard cap on a `history` span (the recovery calendar asks for 126; a year at most).
    private static let historyMaxSpanDays = 366

    /// Exponential backoff after a failed fetch, indexed by consecutive-failure count
    /// (capped at the last entry): 30s → 1m → 2m → 5m → 15m.
    private static let backoffScheduleMs: [Double] = [30_000, 60_000, 120_000, 300_000, 900_000]

    private let auth: WhoopAuthing
    private let tokenStore: WhoopSessionStore
    private let cache: KeyValueStore
    private let session: URLSession

    init(
        auth: WhoopAuthing = WhoopAuth(),
        tokenStore: WhoopSessionStore = WhoopTokenStore(),
        cache: KeyValueStore = EncryptedFileStore.shared,
        session: URLSession? = nil
    ) {
        self.auth = auth
        self.tokenStore = tokenStore
        self.cache = cache
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = WhoopDevice.requestTimeout
            self.session = URLSession(configuration: config)
        }
    }

    /// Cognito USER_PASSWORD_AUTH login. On success the tokens are persisted and `.ok`
    /// is returned; if Whoop demands MFA, returns `.mfa(handle)`.
    func login(email: String, password: String) async -> WhoopLoginResult {
        switch await auth.initiateAuth(email: email, password: password) {
        case let .ok(tokens):
            do { try await tokenStore.saveTokens(tokens) } catch { return .failed }
            return .ok
        case let .mfa(challenge, session, username):
            return .mfa(WhoopMfaHandle(challenge: challenge, session: session, username: username))
        case .failed:
            return .failed
        }
    }

    /// Complete an MFA challenge with the user's code. Persists tokens; true on success.
    func submitMfa(code: String, handle: WhoopMfaHandle) async -> Bool {
        guard let tokens = await auth.respondToMfa(
            challenge: handle.challenge, session: handle.session, username: handle.username, code: code
        ) else { return false }
        do { try await tokenStore.saveTokens(tokens) } catch { return false }
        return true
    }

    /// Remove the stored session + cached snapshots. Local-only.
    func clear() async {
        await tokenStore.clearSession()
        clearSummaryCache()
    }

    func isLinked() async -> Bool {
        await tokenStore.isLinked()
    }

    /// Current strap HR from `/health-tab-bff/v1/health-tab`. Walks the tile tree for the LIVE_HR
    /// tile (type names Whoop is known to use), reading the current bpm + zone + streaming flag.
    /// Not cached: a live value the UI polls; failures/absence return nil and the UI hides it.
    func liveHeartRate() async -> WhoopLiveHr? {
        let result = await authedGet("/health-tab-bff/v1/health-tab", query: [:])
        guard let body = result.body else { return nil }
        let tile = WhoopWalk.findByType(body, "LIVE_HR")
            ?? WhoopWalk.findByType(body, "HEART_RATE_LIVE")
            ?? WhoopWalk.findByType(body, "LIVE_HEART_RATE_TILE")
        let showLive = body["show_live_hr"].boolValue ?? false
        let bpmRaw = tile?["value"].numberValue ?? tile?["bpm"].numberValue ?? tile?["current_bpm"].numberValue
        guard let bpm = bpmRaw, bpm > 0 else {
            return showLive ? WhoopLiveHr(bpm: nil, zone: nil, isRecording: false, lastUpdated: nil) : nil
        }
        let zoneRaw = tile?["zone"].numberValue
        return WhoopLiveHr(
            bpm: Int(bpm.rounded()),
            zone: zoneRaw.map { Int($0) }.flatMap { (0...5).contains($0) ? $0 : nil },
            isRecording: showLive,
            lastUpdated: tile?["updated_at"].stringValue ?? tile?["timestamp"].stringValue
        )
    }

    private var behaviorImpactCache: (fetchedAtMs: Double, impacts: [WhoopBehaviorImpact])?

    /// WHOOP's behavior-impact tiles from `/behavior-impact-service/v1/impact`. Each `tiles[]` carries
    /// `content.impact_cards[]` with the behavior name, WHOOP's own percentage display, and a style
    /// (POSITIVE/NEGATIVE/INSUFFICIENT). We restate them verbatim, no derivation. 15-min cache.
    func behaviorImpacts() async -> [WhoopBehaviorImpact] {
        let nowMs = Date().timeIntervalSince1970 * 1000
        if let cache = behaviorImpactCache, nowMs - cache.fetchedAtMs < Self.cacheTtlMs {
            return cache.impacts
        }
        let result = await authedGet("/behavior-impact-service/v1/impact", query: [:])
        guard let body = result.body else { return behaviorImpactCache?.impacts ?? [] }

        var impacts: [WhoopBehaviorImpact] = []
        for tile in body["tiles"].arrayValue {
            for card in tile["content"]["impact_cards"].arrayValue {
                guard let uuid = card["impact_uuid"].stringValue,
                      let name = card["impact_card_title_display"].stringValue else { continue }
                let style = (card["impact_style"].stringValue ?? "").uppercased()
                let direction: WhoopBehaviorImpact.Direction =
                    style == "POSITIVE" ? .positive : (style == "NEGATIVE" ? .negative : .insufficient)
                impacts.append(WhoopBehaviorImpact(
                    id: uuid,
                    name: name,
                    impactDisplay: direction == .insufficient ? nil : card["impact_percentage_display"].stringValue,
                    direction: direction
                ))
            }
        }
        behaviorImpactCache = (nowMs, impacts)
        return impacts
    }

    /// Outcome of one authed GET: status (0 = network error) + parsed JSON.
    private struct AuthedJson {
        let status: Int
        let body: JSONValue?
    }

    /// GET a data path with a valid bearer token + iOS device headers + ?apiVersion=7. On
    /// 401 it refreshes the token once (via the token store's single-flight gate) and
    /// retries. Status 0 on a transport failure or when not linked. Never throws, never
    /// logs the token.
    private func authedGet(_ path: String, query: [String: String]) async -> AuthedJson {
        guard let token = await tokenStore.getValidAccessToken(),
              let installationId = await tokenStore.installationId()
        else { return AuthedJson(status: 401, body: nil) }

        func attempt(_ bearer: String) async -> AuthedJson {
            guard let url = WhoopDevice.dataURL(path: path, query: query) else {
                return AuthedJson(status: 0, body: nil)
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            for (k, v) in WhoopDevice.headers(installationId: installationId) {
                request.setValue(v, forHTTPHeaderField: k)
            }
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "authorization")

            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse
            else { return AuthedJson(status: 0, body: nil) }
            guard (200..<300).contains(http.statusCode) else {
                return AuthedJson(status: http.statusCode, body: nil)
            }
            return AuthedJson(status: http.statusCode, body: JSONValue.decode(data))
        }

        var result = await attempt(token)
        if result.status == 401 {
            if let refreshed = await tokenStore.getValidAccessToken(), refreshed != token {
                result = await attempt(refreshed)
            }
        }
        return result
    }

    /// Today's local date as YYYY-MM-DD.
    private func todayLocalDate() -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// One day's cached summary entry. `Codable` so it persists into the KeyValueStore.
    /// Holds only display numbers, never tokens.
    private struct CacheEntry: Codable, Sendable {
        let fetchedAt: Double
        let summary: WhoopSummary?
    }

    /// Per-date cache state. Each selected day gets its own entry, in-flight task, and backoff cooldown.
    private final class DayState {
        var cache: CacheEntry?
        var hydrated = false
        var inFlight: Task<WhoopSummary?, Never>?
        var failureCount = 0
        var backoffUntil: Double = 0
    }

    private var dayStates: [String: DayState] = [:]

    private func dayState(_ date: String) -> DayState {
        if let s = dayStates[date] { return s }
        let s = DayState()
        dayStates[date] = s
        return s
    }

    private func nowMs() -> Double { Date().timeIntervalSince1970 * 1000 }

    private func summaryCacheKey(_ date: String) -> String { Self.summaryCachePrefix + date }

    /// Load one day's persisted entry into its in-memory state once (best-effort).
    private func hydrateDay(_ date: String) {
        let s = dayState(date)
        guard !s.hydrated else { return }
        s.hydrated = true
        if let entry = cache.value(CacheEntry.self, forKey: summaryCacheKey(date)) {
            s.cache = entry
        }
    }

    private func persistDay(_ date: String, _ entry: CacheEntry) {
        cache.setValue(entry, forKey: summaryCacheKey(date))
    }

    /// Wipe every day's summary + history + stress cache (in-memory and persisted).
    private func clearSummaryCache() {
        for date in dayStates.keys { cache.removeValue(forKey: summaryCacheKey(date)) }
        for date in stressDayStates.keys { cache.removeValue(forKey: Self.stressCachePrefix + date) }
        dayStates.removeAll()
        stressDayStates.removeAll()
    }

    /// True if at least one real metric (not the always-set timestamps) is set.
    private func hasAnyValue(_ s: WhoopSummary) -> Bool {
        s.recoveryPct != nil || s.recoveryState != nil || s.hrvMs != nil || s.hrvBaselineMs != nil
            || s.rhrBpm != nil || s.rhrBaselineBpm != nil || s.respiratoryRate != nil
            || s.spo2Pct != nil || s.skinTempC != nil || s.sleepPerformancePct != nil
            || s.sleepHours != nil || s.dayStrain != nil || s.calories != nil || s.steps != nil
    }

    /// Live fetch for one day: GET /home, project it, then GET /deep-dive/recovery for the same
    /// day and merge its contributors, finally a sleep-hours fallback. Distinguishes a real
    /// failure from empty data.
    private func fetchSummary(_ date: String) async -> (failed: Bool, summary: WhoopSummary?) {
        let home = await authedGet(Self.homePath, query: ["date": date])
        guard home.status != 401, home.status != 0, home.status < 400, let homeBody = home.body else {
            return (true, nil)
        }

        var summary = WhoopProjections.projectHomeSummary(homeBody)

        let recovery = await authedGet(Self.recoveryDeepDivePath, query: ["date": date])
        if recovery.status == 200, let body = recovery.body {
            summary = WhoopProjections.mergeRecoveryDetail(
                summary, WhoopProjections.projectRecoveryDetail(body, date: date))
        }

        if summary.sleepHours == nil {
            let sleep = await authedGet(Self.sleepDeepDivePath, query: ["date": date])
            if sleep.status == 200, let body = sleep.body,
               let totalMs = WhoopProjections.projectSleepDetail(body, date: date).totalSleepMs {
                summary.sleepHours = (totalMs / 3_600_000 * 100).rounded() / 100
            }
        }

        return (false, hasAnyValue(summary) ? summary : nil)
    }

    /// Run a day's fetch, then update that day's cache + backoff. Keeps good data on failure.
    private func fetchAndCacheDay(_ date: String) async -> WhoopSummary? {
        let s = dayState(date)
        let result = await fetchSummary(date)

        if result.failed {
            s.failureCount += 1
            let idx = min(s.failureCount - 1, Self.backoffScheduleMs.count - 1)
            s.backoffUntil = nowMs() + Self.backoffScheduleMs[idx]
            return s.cache?.summary ?? nil
        }

        s.failureCount = 0
        s.backoffUntil = 0
        let entry = CacheEntry(fetchedAt: nowMs(), summary: result.summary)
        s.cache = entry
        persistDay(date, entry)
        return entry.summary
    }

    /// The dashboard snapshot for `date` (default today). Serves a fresh cached snapshot without
    /// touching the network when < 15 min old, de-dupes concurrent callers per day, and honors
    /// that day's backoff cooldown after failures. `force` bypasses the TTL but still respects
    /// de-dupe + backoff.
    func summary(date: String? = nil, force: Bool = false) async -> WhoopSummary? {
        let day = date ?? todayLocalDate()
        hydrateDay(day)
        let s = dayState(day)
        let now = nowMs()

        if !force, let cached = s.cache, now - cached.fetchedAt < Self.cacheTtlMs {
            return cached.summary
        }
        if now < s.backoffUntil { return s.cache?.summary ?? nil }
        if let inFlight = s.inFlight { return await inFlight.value }

        let task = Task { await self.fetchAndCacheDay(day) }
        s.inFlight = task
        let value = await task.value
        if dayStates[day]?.inFlight == task { dayStates[day]?.inFlight = nil }
        return value
    }

    /// Sleep deep-dive (durations, performance/efficiency/consistency, stages).
    func sleepDetail(date: String? = nil) async -> SleepDetail? {
        let day = date ?? todayLocalDate()
        let result = await authedGet(Self.sleepDeepDivePath, query: ["date": day])
        guard result.status == 200, let body = result.body else { return nil }
        return WhoopProjections.projectSleepDetail(body, date: day)
    }

    /// WHOOP's sleep need from `/coaching-service/v2/sleepneed`. `need_breakdown` (ms) +
    /// `recommended_time_in_bed_formatted["85"]` (the standard 85%-performance tier). Restated as
    /// minutes; nil when the coaching isn't computed yet. Not date-scoped (it's tonight's need).
    func sleepNeed() async -> WhoopSleepNeed? {
        let result = await authedGet("/coaching-service/v2/sleepneed", query: [:])
        guard let body = result.body else { return nil }
        let need = body["need_breakdown"]
        let tier = body["recommended_time_in_bed_formatted"]["85"]
        func mins(_ v: JSONValue) -> Int? { v.numberValue.map { Int(($0 / 60000).rounded()) } }
        let model = WhoopSleepNeed(
            recommendedMinutes: mins(tier["recommended_time_in_bed"]),
            baselineMinutes: mins(need["baseline"]),
            debtMinutes: mins(need["debt"]),
            strainMinutes: mins(need["strain"]),
            napCreditMinutes: mins(need["naps"])
        )
        let anyValue = [model.recommendedMinutes, model.baselineMinutes, model.debtMinutes,
                        model.strainMinutes, model.napCreditMinutes].contains { $0 != nil }
        return anyValue ? model : nil
    }

    /// WHOOP's stored body measurement. Cached for 15 minutes like the other slow-moving reads:
    /// a scale pushes at most a few readings a day, so re-fetching on every screen appearance
    /// would be pure waste.
    ///
    /// Guards `weightKg > 0` deliberately. A WHOOP account with no weight (and the secondary
    /// `custom:account_id` account) answers `0.0`, and logging that as a weigh-in would poison the
    /// trend and the goal math with a zero.
    func bodyMeasurement(force: Bool = false) async -> WhoopBodyMeasurement? {
        let now = Date().timeIntervalSince1970 * 1000
        if !force, let cached = bodyMeasurementCache,
           now - cached.fetchedAt < Self.bodyMeasurementTtlMs {
            return cached.value
        }
        let result = await authedGet(Self.bodyMeasurementPath, query: [:])
        guard result.status == 200, let body = result.body,
              let model = WhoopProjections.projectBodyMeasurement(body)
        else {
            // Keep serving the last good value on a transient failure rather than blanking the
            // weight: WHOOP is the only source, so a dropped request must not look like "no data".
            return bodyMeasurementCache?.value
        }
        bodyMeasurementCache = BodyMeasurementCacheEntry(fetchedAt: now, value: model)
        return model
    }

    /// WHOOP's profile identity fields (age, sex, weight, height).
    ///
    /// The path is user-scoped and the id comes from the access token's `custom:user_id` claim.
    /// Note this is NOT the Cognito `sub` (a UUID) and NOT `custom:account_id` — probing showed
    /// `sub` 404s and `account_id` is a separate, empty account. 24-hour cache: age and sex change
    /// about as slowly as anything in the app.
    func userProfile() async -> WhoopUserProfile? {
        let now = Date().timeIntervalSince1970 * 1000
        if let cached = userProfileCache, now - cached.fetchedAt < Self.userProfileTtlMs {
            return cached.value
        }
        guard let token = await tokenStore.getValidAccessToken(),
              let uid = Self.jwtClaim("custom:user_id", in: token)
        else { return userProfileCache?.value }

        let result = await authedGet("/users-service/v1/users/\(uid)/profile", query: [:])
        guard result.status == 200, let body = result.body else { return userProfileCache?.value }
        let model = WhoopProjections.projectUserProfile(body)
        userProfileCache = UserProfileCacheEntry(fetchedAt: now, value: model)
        return model
    }

    /// Read one claim from a JWT payload. No signature check: this only picks the user id out of a
    /// token the server already accepted, and a forged value would simply 404.
    private static func jwtClaim(_ key: String, in token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
        payload = payload.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload.append("=") }
        guard let data = Data(base64Encoded: payload) else { return nil }
        let json = JSONValue.decode(data)
        if let s = json[key].stringValue { return s }
        if let n = json[key].numberValue { return String(Int(n)) }
        return nil
    }

    /// Strain deep-dive (score + target band, HR-zone time + baselines, steps, strength).
    func strainDetail(date: String? = nil) async -> StrainDetail? {
        let day = date ?? todayLocalDate()
        let result = await authedGet(Self.strainDeepDivePath, query: ["date": day])
        guard result.status == 200, let body = result.body else { return nil }
        return WhoopProjections.projectStrainDetail(body, date: day)
    }

    /// One day's cached stress entry. Holds only the projected detail, never the raw ~1.4 MB
    /// payload, never tokens.
    private struct StressCacheEntry: Codable, Sendable {
        let fetchedAt: Double
        let detail: StressDetail?
    }

    private final class StressDayState {
        var cache: StressCacheEntry?
        var hydrated = false
        var inFlight: Task<StressDetail?, Never>?
    }

    private var stressDayStates: [String: StressDayState] = [:]

    private func stressDayState(_ date: String) -> StressDayState {
        if let s = stressDayStates[date] { return s }
        let s = StressDayState()
        stressDayStates[date] = s
        return s
    }

    /// Load one day's persisted stress entry into memory once (best-effort).
    private func hydrateStressDay(_ date: String) {
        let s = stressDayState(date)
        guard !s.hydrated else { return }
        s.hydrated = true
        if let entry = cache.value(StressCacheEntry.self, forKey: Self.stressCachePrefix + date) {
            s.cache = entry
        }
    }

    /// On failure, serve any stale cached detail rather than re-pulling 1.4 MB.
    private func fetchStressDay(_ date: String) async -> StressDetail? {
        let result = await authedGet(Self.stressPath(date), query: [:])
        guard result.status == 200, let body = result.body else {
            return stressDayState(date).cache?.detail ?? nil
        }
        let detail = WhoopProjections.projectStressDetail(body, date: date)
        let entry = StressCacheEntry(fetchedAt: nowMs(), detail: detail)
        stressDayState(date).cache = entry
        cache.setValue(entry, forKey: Self.stressCachePrefix + date)
        return detail
    }

    /// Stress monitor detail for `date` (default today). Served from a 15-min per-date
    /// cache (survives restarts) and de-duped across concurrent callers; `force` bypasses
    /// the TTL.
    func stressDetail(date: String? = nil, force: Bool = false) async -> StressDetail? {
        let day = date ?? todayLocalDate()
        hydrateStressDay(day)
        let s = stressDayState(day)
        let now = nowMs()

        if !force, let cached = s.cache, now - cached.fetchedAt < Self.cacheTtlMs {
            return cached.detail
        }
        if let inFlight = s.inFlight { return await inFlight.value }

        let task = Task { await self.fetchStressDay(day) }
        s.inFlight = task
        let value = await task.value
        if stressDayStates[day]?.inFlight == task { stressDayStates[day]?.inFlight = nil }
        return value
    }

    /// One persisted history point.
    private struct HistoryCacheEntry: Codable, Sendable {
        let fetchedAt: Double
        let value: Double?
    }

    private func historyCacheKey(_ metric: WhoopHistoryMetric, _ date: String) -> String {
        "\(Self.historyCachePrefix)\(metric.rawValue)/\(date)"
    }

    /// Pull a metric's value out of a day summary, or nil when absent.
    private func metricFromSummary(_ summary: WhoopSummary?, _ metric: WhoopHistoryMetric) -> Double? {
        guard let summary else { return nil }
        switch metric {
        case .recovery: return summary.recoveryPct
        case .hrv: return summary.hrvMs
        case .rhr: return summary.rhrBpm
        case .strain: return summary.dayStrain
        }
    }

    /// N consecutive local dates ending today, newest first.
    private func recentDates(_ days: Int) -> [String] {
        var out: [String] = []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        for i in 0..<days {
            guard let d = calendar.date(byAdding: .day, value: -i, to: today) else { continue }
            let c = calendar.dateComponents([.year, .month, .day], from: d)
            out.append(String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0))
        }
        return out
    }

    /// Read a fresh persisted history point for a day, or nil to signal a (re)fetch.
    /// Today uses the short TTL, past days the long one.
    private func readHistoryPoint(
        _ metric: WhoopHistoryMetric, _ date: String, isToday: Bool
    ) -> HistoryCacheEntry? {
        guard let entry = cache.value(HistoryCacheEntry.self, forKey: historyCacheKey(metric, date))
        else { return nil }
        let ttl = isToday ? Self.cacheTtlMs : Self.historyPastTtlMs
        if nowMs() - entry.fetchedAt >= ttl { return nil }
        return entry
    }

    private func writeHistoryPoint(_ metric: WhoopHistoryMetric, _ date: String, _ value: Double?) {
        cache.setValue(HistoryCacheEntry(fetchedAt: nowMs(), value: value), forKey: historyCacheKey(metric, date))
    }

    /// Dated points for one metric over the last `days` days (oldest → newest), clamped 1…366.
    /// Days with a fresh persisted point (today: 15-min TTL; past days: long TTL) are served from
    /// cache; uncached days are fetched sequentially via `summary` (so the cache, backoff, and
    /// recovery-merge all apply), newest first, capped at 14 network days per call. Days beyond
    /// that budget come back as nil points and stay uncached, so a long window (the 126-day
    /// recovery calendar) backfills progressively across calls instead of being truncated. A nil
    /// from a failed fetch isn't persisted (so a later call retries it); a genuine no-data day is.
    func history(metric: WhoopHistoryMetric, days: Int) async -> [WhoopHistoryPoint] {
        let span = max(1, min(days, Self.historyMaxSpanDays))
        let today = todayLocalDate()
        let dates = recentDates(span)

        var points: [WhoopHistoryPoint] = []
        var budget = Self.historyNetworkBudgetDays
        for date in dates {
            let isToday = date == today
            if let cached = readHistoryPoint(metric, date, isToday: isToday) {
                points.append(WhoopHistoryPoint(date: date, value: cached.value))
                continue
            }
            guard budget > 0 else {
                points.append(WhoopHistoryPoint(date: date, value: nil))
                continue
            }
            budget -= 1
            let daySummary = await summary(date: date, force: false)
            let value = metricFromSummary(daySummary, metric)
            if value != nil || (dayStates[date]?.failureCount ?? 0) == 0 {
                writeHistoryPoint(metric, date, value)
            }
            points.append(WhoopHistoryPoint(date: date, value: value))
        }

        points.reverse()
        return points
    }
}
