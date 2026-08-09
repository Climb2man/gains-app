import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    /// The user's profile, or `nil` until onboarding completes. Drives the first-run gate.
    private(set) var profile: Profile?

    /// True once a profile exists: the app shows the tabs, otherwise the Onboarding flow.
    var isOnboarded: Bool { profile != nil }

    /// The day the date carousel is focused on (local). Defaults to today; screens read this to scope
    /// the Whoop summary / food totals they show.
    var selectedDate: Date

    /// Whether a private Whoop session is linked on this device. Drives the Whoop tab's
    /// live-vs-connect state. Refreshed by `refreshLinks()` (and after a link/unlink).
    var whoopLinked: Bool

    /// Whether an OpenRouter key is stored: gates AI macro estimation. Only a boolean; the key
    /// itself never lives here.
    var hasAIKey: Bool

    /// True for the DEBUG `.sample` container: marks the state as hand-seeded so `load()` is a no-op
    /// and the real (simulator) link checks don't overwrite the populated flags during a screenshot.
    private var isSampleData = false

    /// Whether this is the hand-seeded `.sample` container. Screens whose live service can't reach
    /// real data in a preview/screenshot (e.g. Whoop) read this to serve `SampleData` instead. Always
    /// false in a real build: production data flows through the real services, never `SampleData`.
    var usesSampleData: Bool { isSampleData }

    let profileStore: ProfileStore
    let nutritionStore: NutritionStore
    /// The notes-style food journal: optimistic write + async macro fill.
    let foodLog: FoodLogStore
    /// The nicknamed re-loggable food shortcuts (`food_shortcuts`).
    let savedFoods: SavedFoodsStore
    /// The food-logging preferences (calorie bias + micronutrient toggles) every log consults.
    let foodLogSettings: FoodLogSettingsStore
    /// The notes-style workout journal: optimistic write + async AI parse, the food logger's twin.
    /// Parses freeform notation into the `WorkoutEntry` schema; owns the saved/recent re-log list.
    /// Uses the same BYOK OpenRouter provider as the food path.
    let workoutLog: WorkoutStore
    /// The plain-notes daily journal: no AI, free text saved verbatim, encrypted at rest like the
    /// other logs.
    let journal: JournalStore
    /// The body-weight log: the user's own weigh-ins, encrypted at rest. Feeds the
    /// Overview weight chart, the goal-pace evaluator, and the personal-MCP slice.
    let weightStore: WeightStore
    /// The vision lane (photo / menu / package), over the same BYOK OpenRouter provider. Only the
    /// single base64 image call egresses, on the user's key.
    let foodVision: any FoodVisionService
    /// The encrypted on-device image store: captured photos stay local, referenced by path.
    let foodImageStore: any FoodImageStore
    /// The on-device secure store (Keychain): backs the Whoop session + the OpenRouter key.
    let secureStore: any SecureStore
    /// Cloud MCP sync: pushes a minimized, read-only slice of the record to the user's hosted Gains
    /// MCP server so they can query their own data from an MCP client. Off by default, opt-in from
    /// Health → Settings. Lazy so the slice closure can capture `self`.
    @ObservationIgnored lazy var mcpSync = GainsMCPSync(secureStore: secureStore) { [weak self] in
        guard let self else { return nil }
        return await GainsSliceBuilder.build(appModel: self)
    }
    /// The user's OpenRouter (AI) key store, conforming to the AIProvider key seam.
    let aiKeyStore: OpenRouterKeyStore
    /// The private Whoop client (login / MFA / data). An `actor` behind the `WhoopService` protocol.
    let whoop: any WhoopService
    /// HealthKit body-measurement reads (weight / body-fat / height / lean mass).
    let health: any HealthService

    /// Designated initializer. Defaults construct the production services and wire the AI provider on
    /// top of the Keychain (BYOK); tests and previews inject stubs. Async link checks don't run here
    /// (an init can't await). Call `refreshLinks()` from the app entry's `.task`.
    init(
        profileStore: ProfileStore? = nil,
        nutritionStore: NutritionStore? = nil,
        foodLog: FoodLogStore? = nil,
        savedFoods: SavedFoodsStore? = nil,
        foodLogSettings: FoodLogSettingsStore? = nil,
        workoutLog: WorkoutStore? = nil,
        journal: JournalStore? = nil,
        secureStore: any SecureStore = KeychainStore(),
        whoop: (any WhoopService)? = nil,
        health: any HealthService = HealthKitService(),
        selectedDate: Date = Date()
    ) {
        let profileStore = profileStore ?? ProfileStore()
        let nutritionStore = nutritionStore ?? NutritionStore()
        self.profileStore = profileStore
        self.nutritionStore = nutritionStore
        self.secureStore = secureStore
        let aiKeyStore = OpenRouterKeyStore(secureStore: secureStore)
        self.aiKeyStore = aiKeyStore
        self.whoop = whoop ?? WhoopClient()
        self.health = health
        self.foodLogSettings = foodLogSettings ?? FoodLogSettingsStore()
        let savedFoods = savedFoods ?? SavedFoodsStore()
        self.savedFoods = savedFoods
        let foodRouter = FoodLoggingRouter(
            savedFoods: savedFoods,
            cache: NutritionCache(),
            ai: FoodAINutritionService(provider: OpenRouterProvider(keyProvider: aiKeyStore))
        )
        let foodLog = foodLog
            ?? FoodLogStore(service: foodRouter)
        self.foodLog = foodLog
        foodLog.entriesDidChange = { nutritionStore.mirrorJournal($0) }
        nutritionStore.mirrorJournal(foodLog.entries)
        self.workoutLog = workoutLog
            ?? WorkoutStore(service: WorkoutParseService(provider: OpenRouterProvider(keyProvider: aiKeyStore)))
        self.journal = journal ?? JournalStore()
        self.weightStore = WeightStore()
        self.foodVision = OpenRouterFoodVisionService(
            provider: OpenRouterProvider(keyProvider: aiKeyStore)
        )
        self.foodImageStore = (try? LocalFoodImageStore()) ?? NoopFoodImageStore()
        self.profile = profileStore.profile
        self.selectedDate = selectedDate
        self.whoopLinked = false
        self.hasAIKey = aiKeyStore.hasKey
        foodLog.entriesDidChange = { [weak self] entries in
            self?.nutritionStore.mirrorJournal(entries)
            self?.mcpSync.scheduleSync()
        }
        weightStore.didChange = { [weak self] in self?.mcpSync.scheduleSync() }
    }

    /// Resolve launch state: re-read the profile and the two connection flags. Cheap + safe to call
    /// again (e.g. on `.task` / foreground).
    func load() async {
        seedDevAIKeyIfNeeded()

        guard !isSampleData else {
            hasAIKey = aiKeyStore.hasKey
            return
        }
        profileStore.reload()
        profile = profileStore.profile
        await refreshLinks()
    }

    /// DEBUG-only: seed the developer OpenRouter key from `DevSecrets` into the Keychain, but only when
    /// no key is stored, so a fresh simulator reaches the AI lanes out of the box. `DevSecrets` is the
    /// committed placeholder (empty by default); edit it locally with your own key and never commit a
    /// real one. A no-op when any key already exists (including a hand-entered BYOK key), when the
    /// placeholder is empty, or in a release build.
    ///
    /// A rotated dev key needs a one-time "Remove key" in Settings (relaunch then reseeds), the price
    /// of never clobbering a real key. The key value is never logged, only the boolean `hasAIKey`.
    private func seedDevAIKeyIfNeeded() {
        #if DEBUG
        guard !aiKeyStore.hasKey else { return }
        let devKey = DevSecrets.openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !devKey.isEmpty else { return }
        aiKeyStore.save(devKey)
        hasAIKey = aiKeyStore.hasKey
        print("[Gains][DEBUG] Seeded dev OpenRouter key into Keychain; hasAIKey=\(hasAIKey)")
        #endif
    }

    /// Re-check the Whoop link (async) + the OpenRouter-key presence (sync). Call after a link/unlink
    /// or after the Settings "add key" flow.
    func refreshLinks() async {
        hasAIKey = aiKeyStore.hasKey
        whoopLinked = await whoop.isLinked()
        await mcpSync.syncIfEnabled()
        await syncProfileFromWhoop()
        await syncWeightFromWhoop()
        refreshWeeklyGoalsIfDue()
    }

    /// The last time WHOOP's weight was successfully read. Drives the "Synced from WHOOP" label.
    var lastWhoopWeightSync: Date?

    /// Adopt WHOOP's stored weight. WHOOP is this app's ONLY weight source — a smart scale pushes
    /// to WHOOP, WHOOP flows here, and there is no manual entry anywhere in the UI.
    ///
    /// No-op when unlinked, on the sample container, when WHOOP holds no weight, or when today's
    /// entry already matches — the last case matters because `logWeight` persists and fires
    /// `didChange`, which re-pushes the personal-MCP slice.
    ///
    /// Trade-off accepted deliberately: WHOOP's private API can break without notice, and with no
    /// manual fallback the weight trend and goal maths stall until it recovers. The last synced
    /// value stays on disk, so nothing is lost — it just stops advancing.
    @discardableResult
    func syncWeightFromWhoop() async -> Bool {
        guard !isSampleData, whoopLinked else { return false }
        guard let measurement = await whoop.bodyMeasurement() else { return false }

        lastWhoopWeightSync = Date()

        // Keep the PROFILE weight in step first, and unconditionally.
        //
        // This used to sit after the de-dup guard below, which meant that once today's weigh-in
        // matched WHOOP the whole function returned early and the profile was never corrected — so
        // `profile.weightKg` (shown in the Overview metric strip, and the input to every BMR
        // calculation) could stay stale indefinitely while the weight card showed the right number.
        // That is why two different weights could appear in the app at once.
        if var current = profile, abs(current.weightKg - measurement.weightKg) >= 0.005 {
            current.weightKg = measurement.weightKg
            updateProfile(current)
        }

        // The weigh-in log only needs a new row when the value actually moved: `log` replaces the
        // entry for the day, so re-writing an identical one would just churn persistence and the
        // personal-MCP slice.
        let todayKey = FoodLogStore.dayKey(Date())
        if let latest = weightStore.entries.last, latest.date == todayKey,
           abs(latest.kg - measurement.weightKg) < 0.005 {
            return false
        }
        weightStore.log(lb: Units.kgToLb(measurement.weightKg))
        return true
    }

    /// Mean WHOOP day-strain over the last `days` days, ignoring days with no score. Advisory input
    /// to the activity suggestion in Goals; nil when unlinked or WHOOP has no scored days yet.
    func whoopStrainAverage(days: Int = 7) async -> Double? {
        guard !isSampleData, whoopLinked else { return nil }
        let points = await whoop.history(metric: .strain, days: days).compactMap(\.value)
        guard !points.isEmpty else { return nil }
        return points.reduce(0, +) / Double(points.count)
    }

    /// Fill age / sex / height from WHOOP so none of them is ever typed. Weight is left to
    /// `syncWeightFromWhoop`, which also writes the weigh-in trend.
    ///
    /// Only fills fields that actually differ, and never overwrites a known value with nil — a
    /// partially-filled WHOOP profile must not blank out a good local one.
    @discardableResult
    func syncProfileFromWhoop() async -> Bool {
        guard !isSampleData, whoopLinked, var current = profile else { return false }
        guard let remote = await whoop.userProfile() else { return false }

        var changed = false
        if let age = remote.ageYears, age != current.ageYears {
            current.ageYears = age
            changed = true
        }
        if let sex = remote.sex, sex != current.sex {
            current.sex = sex
            changed = true
        }
        if let meters = remote.heightMeters {
            let cm = (meters * 100).rounded()
            if abs(cm - current.heightCm) >= 0.5 {
                current.heightCm = cm
                changed = true
            }
        }
        guard changed else { return false }
        updateProfile(current)
        return true
    }

    /// Recompute calorie + macro targets from the trailing 7-day average weight, at most once per
    /// ISO week.
    ///
    /// Weekly rather than daily on purpose: a smart scale pushes a figure most mornings, and normal
    /// day-to-day swing (hydration, food in transit) is a pound or two. Recomputing on every reading
    /// would move the targets constantly for no physiological reason, which is unsettling mid-cut.
    /// So the average is taken and applied once a week — in practice the first time the app is
    /// opened on or after Monday.
    ///
    /// No-op without a goal recipe, which is also the migration path: a recipe written by the old
    /// model stores a direction like "lose1" that no longer resolves, so nothing is recomputed and
    /// the existing targets stand until a goal is picked afresh.
    @discardableResult
    func refreshWeeklyGoalsIfDue(now: Date = Date()) -> Bool {
        guard !isSampleData, let profile, nutritionStore.goalRecipe != nil else { return false }
        let week = Self.isoWeekKey(now)
        guard UserDefaults.standard.string(forKey: Self.weeklyGoalRefreshKey) != week else {
            return false
        }
        UserDefaults.standard.set(week, forKey: Self.weeklyGoalRefreshKey)
        nutritionStore.autoAdjustGoals(profile: profile)
        return true
    }

    private static let weeklyGoalRefreshKey = "@gains/goals/lastWeeklyRefresh"

    /// "2026-W32" — ISO year + week, so the value changes exactly once a week, on Monday
    /// (ISO weeks start Monday).
    private static func isoWeekKey(_ date: Date) -> String {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        let parts = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(parts.yearForWeekOfYear ?? 0)-W\(parts.weekOfYear ?? 0)"
    }

    /// Back-fill the weight trend from Apple Health history (the user's smart-scale weigh-ins). Runs
    /// only when Apple Health is connected (an explicit consent step), a no-op otherwise, on the
    /// sample container, or when there's nothing new. Display only: the canonical profile weight keeps
    /// its separate confirm-before-write flow. Safe to call on launch and right after connecting Health.
    func importHealthWeightHistory(days: Int = 365) async {
        guard !isSampleData else { return }
        guard UserDefaults.standard.bool(forKey: AppleHealthKeys.weightConnected) else { return }
        let samples = await health.weightSamplesKg(sinceDays: days)
        weightStore.importHealthSamples(samples)
    }

    /// Persist + adopt the onboarding profile, flipping the first-run gate so the tabs mount.
    /// Called from the Onboarding flow's `onComplete`.
    func completeOnboarding(_ profile: Profile) {
        profileStore.save(profile)
        self.profile = profile
    }

    /// Replace the in-memory profile after an edit elsewhere (keeps the gate's copy in sync).
    /// Replace the in-memory profile after an edit elsewhere (keeps the gate's copy in sync).
    ///
    /// `recomputeGoals` defaults to FALSE, which is the important part. This used to recompute
    /// unconditionally, and since `logWeight` calls it on every WHOOP weight sync, calorie and macro
    /// targets were being rebuilt daily from that morning's raw scale reading — bypassing the weekly
    /// refresh entirely and reintroducing exactly the day-to-day drift it exists to prevent.
    ///
    /// Automatic paths (weight sync, WHOOP profile sync) therefore leave the targets alone and let
    /// `refreshWeeklyGoalsIfDue` own them. Only a user-initiated profile edit asks for an immediate
    /// recompute, and even that uses the smoothed weight so it agrees with the weekly result.
    func updateProfile(_ profile: Profile, recomputeGoals: Bool = false) {
        profileStore.save(profile)
        self.profile = profile
        guard recomputeGoals else { return }
        nutritionStore.autoAdjustGoals(profile: profile)
    }

    /// Record a weigh-in (lb): append to the weight log and update the profile's current weight so the
    /// goal-pace evaluator and auto-adjust track the latest number. The store's `didChange` re-pushes
    /// the personal-MCP slice (debounced, no-op unless opt-in).
    func logWeight(lb: Double, bodyFatPct: Double? = nil, on date: Date = Date()) {
        weightStore.log(lb: lb, on: date, bodyFatPct: bodyFatPct)
        if var updated = profile {
            updated.weightKg = Units.lbToKg(lb)
            updateProfile(updated)
        }
    }

    /// Reset to the onboarding gate (sign-out / start-over). Clears the stored profile; does not revoke
    /// the Whoop session at the server (that's the connect screen's job).
    func resetProfile() {
        profileStore.clear()
        profile = nil
    }
}

#if DEBUG
extension AppModel {
    /// A fully-populated AppModel for previews and DEBUG screenshots: a sample profile (20yo male,
    /// 6'0", 200 lb), an in-memory food log, and the "linked + key present" flags so every screen
    /// renders its live state. Uses an isolated UserDefaults suite so seeded data never touches real
    /// on-device data. The Whoop/health/AI services stay real types but are never hit. Screens read
    /// sample data directly via `SampleData` and the seeded NutritionStore.
    @MainActor
    static var sample: AppModel {
        let suite = UserDefaults(suiteName: "gains.sample.preview") ?? .standard
        suite.removePersistentDomain(forName: "gains.sample.preview")
        let kv = UserDefaultsStore(defaults: suite)

        let profileStore = ProfileStore(store: kv)
        profileStore.save(SampleData.profile)

        let nutritionStore = NutritionStore(store: kv)
        nutritionStore.setGoals(SampleData.goals)
        for meal in SampleData.savedMeals {
            nutritionStore.saveMeal(SavedMealInput(
                name: meal.name,
                calories: meal.calories,
                proteinG: meal.proteinG,
                carbsG: meal.carbsG,
                fatG: meal.fatG
            ))
        }

        let savedFoods = SavedFoodsStore(store: kv)
        savedFoods.seed(SampleData.foodShortcuts)
        let foodLogSettings = FoodLogSettingsStore(store: kv)
        foodLogSettings.setBias(.overestimateHigh)
        foodLogSettings.setMicronutrients(MicronutrientToggles(sugar: true, fiber: true, sodium: false))
        let foodLog = FoodLogStore(
            service: FoodLoggingRouter(
                savedFoods: savedFoods,
                cache: NutritionCache(store: kv),
                ai: FoodAINutritionService(provider: OpenRouterProvider(
                    keyProvider: OpenRouterKeyStore(secureStore: KeychainStore())
                ))
            ),
            store: kv
        )
        foodLog.seedToday(SampleData.foodLogLines)
        foodLog.seedHistory(SampleData.foodLogHistory(days: 21))

        let workoutLog = WorkoutStore(
            service: WorkoutParseService(provider: OpenRouterProvider(
                keyProvider: OpenRouterKeyStore(secureStore: KeychainStore())
            )),
            store: kv
        )
        workoutLog.seedToday(SampleData.workoutLogSessions)
        workoutLog.seedShortcuts(SampleData.workoutShortcuts)

        let journal = JournalStore(store: kv)
        journal.seedToday([
            "Slept great, felt strong on bench today.",
            "Skipped the afternoon coffee, want to see if it helps tonight's sleep.",
        ])

        let model = AppModel(
            profileStore: profileStore,
            nutritionStore: nutritionStore,
            foodLog: foodLog,
            savedFoods: savedFoods,
            foodLogSettings: foodLogSettings,
            workoutLog: workoutLog,
            journal: journal,
            selectedDate: SampleData.referenceDate
        )
        model.profile = SampleData.profile
        model.whoopLinked = true
        model.hasAIKey = true
        model.isSampleData = true
        return model
    }

    /// A fresh-but-onboarded container for the empty-state a new tester sees right after onboarding:
    /// a profile and goals exist, but nothing is logged and nothing is linked. Isolated suite, no
    /// seeded data, Whoop/AI flags off. Launch with `-emptyState YES`.
    @MainActor
    static var emptyOnboarded: AppModel {
        let suite = UserDefaults(suiteName: "gains.empty.preview") ?? .standard
        suite.removePersistentDomain(forName: "gains.empty.preview")
        let kv = UserDefaultsStore(defaults: suite)

        let profileStore = ProfileStore(store: kv)
        profileStore.save(SampleData.profile)

        let nutritionStore = NutritionStore(store: kv)
        nutritionStore.setGoals(SampleData.goals)

        let savedFoods = SavedFoodsStore(store: kv)
        let foodLogSettings = FoodLogSettingsStore(store: kv)
        let foodLog = FoodLogStore(
            service: FoodLoggingRouter(
                savedFoods: savedFoods,
                cache: NutritionCache(store: kv),
                ai: FoodAINutritionService(provider: OpenRouterProvider(
                    keyProvider: OpenRouterKeyStore(secureStore: KeychainStore())
                ))
            ),
            store: kv
        )
        let workoutLog = WorkoutStore(
            service: WorkoutParseService(provider: OpenRouterProvider(
                keyProvider: OpenRouterKeyStore(secureStore: KeychainStore())
            )),
            store: kv
        )

        let model = AppModel(
            profileStore: profileStore,
            nutritionStore: nutritionStore,
            foodLog: foodLog,
            savedFoods: savedFoods,
            foodLogSettings: foodLogSettings,
            workoutLog: workoutLog,
            journal: JournalStore(store: kv),
            selectedDate: SampleData.referenceDate
        )
        model.profile = SampleData.profile
        model.whoopLinked = false
        model.hasAIKey = false
        model.isSampleData = false
        return model
    }
}
#endif
