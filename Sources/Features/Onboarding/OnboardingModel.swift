import Observation
import SwiftUI

@MainActor
@Observable
final class OnboardingModel {
    /// The ordered flow. `welcome` precedes the numbered steps (the progress dots count the rest).
    /// NOTE: `whoop` comes BEFORE `profile` deliberately. Weight is WHOOP-sourced (a smart scale
    /// pushes to WHOOP), and the profile step shows it read-only — so the link has to exist first
    /// or there would be nothing to show. Upstream had profile first, when weight was typed in.
    enum Step: Int, CaseIterable {
        case welcome, whoop, profile, health, aiKey, goals

        /// Steps that show the progress dots / count toward them (everything after the welcome intro).
        static let dotted: [Step] = [.whoop, .profile, .health, .aiKey, .goals]
    }

    private(set) var step: Step = OnboardingModel.initialStep

    /// DEBUG-only: lets a screenshot harness deep-link the flow to a step via the `-onboardingStep`
    /// launch argument, mirroring `RootTabView`'s `initialTab`. Release builds always open on
    /// `.welcome` (no launch-arg path).
    private static var initialStep: Step {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "onboardingStep") {
            switch raw {
            case "profile": return .profile
            case "whoop": return .whoop
            case "health": return .health
            case "aiKey": return .aiKey
            case "goals": return .goals
            default: return .welcome
            }
        }
        #endif
        return .welcome
    }

    var sex: Sex?
    var ageYears = 30
    var feet = 5
    var inches = 10
    /// Seeded from WHOOP once linked (see `pullBodyFromWhoop`). The 165 default only survives when
    /// WHOOP holds no weight, so onboarding can still finish rather than dead-ending.
    var weightLb = 165
    /// True once WHOOP supplied the weight, so the profile step can say where the number came from.
    private(set) var weightFromWhoop = false

    /// Valid once sex is picked and age/height/weight are positive (feet > 0; inches optional).
    /// The full guard holds even if a stepper is dialed to its floor.
    var profileValid: Bool {
        guard sex != nil else { return false }
        guard ageYears > 0, feet > 0, weightLb > 0 else { return false }
        return true
    }

    var whoopEmail = ""
    var whoopPassword = ""
    /// MFA code the user types after Whoop challenges the login.
    var whoopMfaCode = ""
    /// The opaque MFA handle carried from login into submitMfa (set only while a challenge is open).
    private(set) var whoopMfaHandle: WhoopMfaHandle?
    private(set) var whoopBusy = false
    private(set) var whoopLinked = false
    /// User-facing error for the Whoop step; never contains the password.
    private(set) var whoopError: String?

    var whoopAwaitingMfa: Bool { whoopMfaHandle != nil }
    var whoopCredentialsValid: Bool {
        !whoopEmail.trimmed.isEmpty && !whoopPassword.isEmpty
    }

    private(set) var healthAvailable = false
    private(set) var healthBusy = false
    private(set) var healthConnected = false

    var aiKeyDraft = ""
    private(set) var aiKeySaved = false

    /// The two goal inputs. Calories and macros are DERIVED from these plus the WHOOP-sourced
    /// profile — there is no manual calorie or macro entry anywhere in the app.
    var goalDirection: GoalCalculator.GoalDirection?
    var activityLevel: GoalCalculator.ActivityLevel?
    /// 7-day mean WHOOP day-strain, loaded once the account links. Advisory only.
    private(set) var avgDayStrain: Double?

    /// The activity band WHOOP's recent strain points at, or nil when there is no strain yet.
    var suggestedActivity: GoalCalculator.ActivityLevel? {
        avgDayStrain.map(GoalCalculator.suggestedActivity(avgDayStrain:))
    }

    /// The computed targets, or nil until both choices are made and the profile is valid.
    var goalEstimate: GoalCalculator.Result? {
        guard let profile = buildProfile(), let goalDirection, let activityLevel else { return nil }
        return GoalCalculator.estimate(profile: profile, activity: activityLevel, goal: goalDirection)
    }

    /// Daily step target: the one goal still set by hand, since it is not part of the calorie model
    /// and WHOOP exposes no step goal to read.
    var stepsGoal = 0

    /// Calorie-estimation bias picked in the goals step (defaults balanced). Persisted to
    /// `FoodLogSettingsStore` on finish.
    var calorieBias: CalorieBias = .balanced

    /// Valid once a goal and an activity level are chosen (which is what produces `goalEstimate`)
    /// and a step target is set.
    var goalsValid: Bool { goalEstimate != nil && stepsGoal > 0 }

    /// The goals as a model, or `nil` when invalid. Every macro is derived, never typed.
    var goals: Goals? {
        guard let estimate = goalEstimate, stepsGoal > 0 else { return nil }
        return Goals(
            calorieGoal: Double(estimate.calorieGoal),
            proteinGoal: Double(estimate.proteinGoal),
            fatGoal: Double(estimate.fatGoal),
            carbGoal: Double(estimate.carbGoal),
            stepsGoal: stepsGoal
        )
    }

    /// The recipe to persist so the weekly refresh can re-derive these targets later.
    var goalRecipe: GoalRecipe? {
        guard let estimate = goalEstimate else { return nil }
        return GoalRecipe(activity: estimate.activity.rawValue, direction: estimate.goal.rawValue)
    }

    /// Load the strain average used to suggest an activity band. Called after WHOOP links.
    func loadStrainSuggestion() async {
        let points = await whoop.history(metric: .strain, days: 7).compactMap(\.value)
        avgDayStrain = points.isEmpty ? nil : points.reduce(0, +) / Double(points.count)
    }

    private let whoop: any WhoopService
    private let aiKeyStore: OpenRouterKeyStore
    private let health: any HealthService

    init(whoop: any WhoopService, aiKeyStore: OpenRouterKeyStore, health: any HealthService) {
        self.whoop = whoop
        self.aiKeyStore = aiKeyStore
        self.health = health
        healthAvailable = health.isAvailable()
        // Only the step target needs a starting value now. Calories and macros are derived from the
        // goal + activity choice, so seeding them would just be a number the user never chose.
        stepsGoal = Goals.default.stepsGoal
    }

    /// Advance one step. No-op past the end.
    func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    /// Go back one step. No-op before the first.
    func back() {
        guard let prev = Step(rawValue: step.rawValue - 1) else { return }
        if step == .whoop { resetWhoopChallenge() }
        step = prev
    }

    /// Cached `createdAt` stamper. `ISO8601DateFormatter` init is expensive and `buildProfile()`
    /// runs on every goals-step render, so it must not be constructed per call.
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Build the canonical metric profile from the imperial inputs (converted via Core/Units).
    /// Returns `nil` if the form is invalid, so the caller can bounce back.
    func buildProfile() -> Profile? {
        guard let sex, ageYears > 0, feet > 0, weightLb > 0 else { return nil }
        let heightCm = (Units.ftInToCm(feet: Double(feet), inches: Double(inches))).rounded()
        let weightKg = (Units.lbToKg(Double(weightLb)) * 10).rounded() / 10
        return Profile(
            name: nil,
            sex: sex,
            ageYears: ageYears,
            heightCm: heightCm,
            weightKg: weightKg,
            createdAt: Self.isoFormatter.string(from: Date())
        )
    }

    /// Attempt a Whoop login. On success marks linked and advances; on an MFA challenge opens the
    /// code field; on failure shows a generic error. Never logs the password.
    func connectWhoop() async {
        guard whoopCredentialsValid, !whoopBusy else { return }
        whoopBusy = true
        whoopError = nil
        let result = await whoop.login(email: whoopEmail.trimmed, password: whoopPassword)
        whoopBusy = false
        switch result {
        case .ok:
            await finishWhoopSuccess()
        case let .mfa(handle):
            whoopMfaHandle = handle
        case .failed:
            whoopError = "Couldn't sign in. Check your email and password and try again."
        }
    }

    /// Submit the MFA code for an open Whoop challenge. On success marks linked + advances.
    func submitWhoopMfa() async {
        guard let handle = whoopMfaHandle, !whoopMfaCode.trimmed.isEmpty, !whoopBusy else { return }
        whoopBusy = true
        whoopError = nil
        let ok = await whoop.submitMfa(code: whoopMfaCode.trimmed, handle: handle)
        whoopBusy = false
        if ok {
            await finishWhoopSuccess()
        } else {
            whoopError = "That code didn't work. Check the code and try again."
        }
    }

    private func finishWhoopSuccess() async {
        whoopLinked = true
        whoopPassword = ""
        resetWhoopChallenge()
        await pullBodyFromWhoop()
        await loadStrainSuggestion()
        advance()
    }

    /// Adopt WHOOP's stored weight (and height, which arrives in the same call) so the profile step
    /// can present them read-only. Weight has no manual entry anywhere in the app — WHOOP owns it.
    ///
    /// Deliberately leaves the defaults untouched when WHOOP holds nothing, so onboarding can still
    /// be completed and the goal maths still has an input; the value corrects itself on the first
    /// successful sync afterwards.
    private func pullBodyFromWhoop() async {
        guard let measurement = await whoop.bodyMeasurement() else { return }
        weightFromWhoop = true
        weightLb = Int(Units.kgToLb(measurement.weightKg).rounded())
        if let meters = measurement.heightMeters, meters > 0 {
            let ftIn = Units.cmToFtIn(meters * 100)
            feet = ftIn.feet
            inches = ftIn.inches
        }
    }

    /// Clear any open MFA challenge state (handle + typed code + error).
    private func resetWhoopChallenge() {
        whoopMfaHandle = nil
        whoopMfaCode = ""
        whoopError = nil
    }

    /// Request HealthKit read access, then advance. Doesn't import a weight (the about-you step
    /// already captured it); it only establishes the grant so Settings can re-read later. Persists
    /// the "connected" flag (`AppleHealthKeys`) if a weight comes back, otherwise only "requested".
    /// A no-op that just advances on a device without HealthKit.
    func connectAppleHealth() async {
        guard !healthBusy else { return }
        healthBusy = true
        await health.requestAuthorization()
        let kg = await health.latestWeightKg()
        UserDefaults.standard.set(true, forKey: AppleHealthKeys.weightRequested)
        if kg != nil { UserDefaults.standard.set(true, forKey: AppleHealthKeys.weightConnected) }
        healthBusy = false
        healthConnected = true
        advance()
    }

    /// Persist the typed OpenRouter key to the Keychain, then mark saved, clear the draft, and
    /// advance. Never logs the key. A blank/whitespace draft is a no-op.
    func saveAIKey() {
        guard aiKeyStore.save(aiKeyDraft) else { return }
        aiKeySaved = true
        aiKeyDraft = ""
        advance()
    }

}

private extension String {
    /// Whitespace-trimmed copy; inputs are user-typed, so trim before validating.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
