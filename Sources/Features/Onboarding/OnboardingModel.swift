import Observation
import SwiftUI

@MainActor
@Observable
final class OnboardingModel {
    /// The ordered flow. `welcome` precedes the numbered steps (the progress dots count the rest).
    enum Step: Int, CaseIterable {
        case welcome, profile, whoop, health, aiKey, goals

        /// Steps that show the progress dots / count toward them (everything after the welcome intro).
        static let dotted: [Step] = [.profile, .whoop, .health, .aiKey, .goals]
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
    var weightLb = 165

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

    var calorieGoal = 0
    var proteinGoal = 0
    var fatGoal = 0
    var carbGoal = 0
    /// Daily step target, a first-class goal alongside the macros. Whole steps, so Int.
    var stepsGoal = 0

    /// Calorie-estimation bias picked in the goals step (defaults balanced). Persisted to
    /// `FoodLogSettingsStore` on finish.
    var calorieBias: CalorieBias = .balanced

    /// All goal values must be valid (calories + steps positive ints; macros non-negative ints).
    var goalsValid: Bool {
        guard calorieGoal > 0 else { return false }
        guard proteinGoal >= 0, fatGoal >= 0, carbGoal >= 0 else { return false }
        guard stepsGoal > 0 else { return false }
        return true
    }

    /// The goals as a model, or `nil` when invalid.
    var goals: Goals? {
        guard goalsValid else { return nil }
        return Goals(
            calorieGoal: Double(calorieGoal),
            proteinGoal: Double(proteinGoal),
            fatGoal: Double(fatGoal),
            carbGoal: Double(carbGoal),
            stepsGoal: stepsGoal
        )
    }

    private let whoop: any WhoopService
    private let aiKeyStore: OpenRouterKeyStore
    private let health: any HealthService

    init(whoop: any WhoopService, aiKeyStore: OpenRouterKeyStore, health: any HealthService) {
        self.whoop = whoop
        self.aiKeyStore = aiKeyStore
        self.health = health
        healthAvailable = health.isAvailable()
        let d = Goals.default
        calorieGoal = Int(d.calorieGoal)
        proteinGoal = Int(d.proteinGoal)
        fatGoal = Int(d.fatGoal)
        carbGoal = Int(d.carbGoal)
        stepsGoal = d.stepsGoal
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
            finishWhoopSuccess()
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
            finishWhoopSuccess()
        } else {
            whoopError = "That code didn't work. Check the code and try again."
        }
    }

    private func finishWhoopSuccess() {
        whoopLinked = true
        whoopPassword = ""
        resetWhoopChallenge()
        advance()
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

    /// Apply a calculator estimate to the four goal fields. The user still edits and confirms
    /// (never silent-write).
    func applyEstimate(_ result: GoalCalculator.Result) {
        calorieGoal = result.calorieGoal
        proteinGoal = result.proteinGoal
        fatGoal = result.fatGoal
        carbGoal = result.carbGoal
    }
}

private extension String {
    /// Whitespace-trimmed copy; inputs are user-typed, so trim before validating.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
