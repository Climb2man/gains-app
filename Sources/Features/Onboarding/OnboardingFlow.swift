import SwiftUI

struct OnboardingFlow: View {
    /// App container (dependency source + first-run gate). Read from the environment so the flow
    /// drives the same `WhoopService` / key store as the rest of the app, and finishing flips
    /// `AppModel.profile` to mount the tabs.
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Finish-handler override for previews/tests. When `nil`, the flow persists the profile and
    /// goals onto the environment `AppModel`.
    private let onComplete: ((Profile, Goals) -> Void)?

    /// The flow state machine, built lazily on first appear because `@State` can't read the
    /// environment `AppModel` (its Whoop client + key store) at init.
    @State private var model: OnboardingModel?

    /// Production entry point used by the app shell: no args, reads everything from the environment.
    init() {
        self.onComplete = nil
    }

    /// Preview/test entry point: inject the finish handler. Dependencies still come from the
    /// environment `AppModel`.
    init(onComplete: @escaping (Profile, Goals) -> Void) {
        self.onComplete = onComplete
    }

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                Color.clear
                    .onAppear { model = OnboardingModel(whoop: appModel.whoop, aiKeyStore: appModel.aiKeyStore, health: appModel.health) }
            }
        }
        .background(Theme.Colors.background)
    }

    @ViewBuilder
    private func content(_ model: OnboardingModel) -> some View {
        if model.step == .welcome {
            WelcomeScreen { advance(model) }
        } else {
            stepScaffold(model)
        }
    }

    private func stepScaffold(_ model: OnboardingModel) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            topBar(model)
            ScrollView {
                stepBody(model)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.top, Theme.Spacing.sm)
                    .transition(stepTransition)
                    .id(model.step)
            }
            .scrollDismissesKeyboard(.interactively)
            footer(model)
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.xl)
        }
        .padding(.top, Theme.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
    }

    /// The entering/leaving transition for a step body. Reduce Motion → a plain cross-fade (no slide).
    private var stepTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    private func topBar(_ model: OnboardingModel) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            IconButton(systemName: "chevron.backward") { back(model) }
                .accessibilityLabel("Back")

            if let dotIndex = OnboardingModel.Step.dotted.firstIndex(of: model.step) {
                StepProgressBar(current: dotIndex + 1, total: OnboardingModel.Step.dotted.count)
            }

            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, Theme.Spacing.xl)
    }

    @ViewBuilder
    private func stepBody(_ model: OnboardingModel) -> some View {
        switch model.step {
        case .welcome: EmptyView()
        case .profile: AboutYouStep(model: model)
        case .whoop: ConnectWhoopStep(model: model)
        case .health: ConnectAppleHealthStep(model: model)
        case .aiKey: AIKeyStep(model: model)
        case .goals: GoalsStep(model: model, profile: model.buildProfile())
        }
    }

    @ViewBuilder
    private func footer(_ model: OnboardingModel) -> some View {
        switch model.step {
        case .welcome:
            EmptyView()

        case .profile:
            AppButton(title: "Continue", kind: .primary) { advance(model) }
                .disabled(!model.profileValid)
                .opacity(model.profileValid ? 1 : 0.5)

        case .whoop:
            VStack(spacing: Theme.Spacing.sm) {
                if model.whoopAwaitingMfa {
                    let disabled = model.whoopBusy || model.whoopMfaCode.isEmpty
                    AppButton(title: model.whoopBusy ? "Verifying…" : "Verify code", kind: .primary) {
                        Task { await model.submitWhoopMfa() }
                    }
                    .disabled(disabled)
                    .opacity(disabled ? 0.5 : 1)
                } else {
                    let disabled = model.whoopBusy || !model.whoopCredentialsValid
                    AppButton(title: model.whoopBusy ? "Connecting…" : "Connect Whoop", kind: .primary) {
                        Task { await model.connectWhoop() }
                    }
                    .disabled(disabled)
                    .opacity(disabled ? 0.5 : 1)
                }
                AppButton(title: "Connect later", kind: .secondary) { advance(model) }
                    .disabled(model.whoopBusy)
                    .opacity(model.whoopBusy ? 0.5 : 1)
            }

        case .health:
            VStack(spacing: Theme.Spacing.sm) {
                if model.healthAvailable {
                    AppButton(title: model.healthBusy ? "Connecting…" : "Connect Apple Health", kind: .primary) {
                        Task { await model.connectAppleHealth() }
                    }
                    .disabled(model.healthBusy)
                    .opacity(model.healthBusy ? 0.5 : 1)
                    AppButton(title: "Connect later", kind: .secondary) { advance(model) }
                        .disabled(model.healthBusy)
                        .opacity(model.healthBusy ? 0.5 : 1)
                } else {
                    AppButton(title: "Continue", kind: .primary) { advance(model) }
                }
            }

        case .aiKey:
            VStack(spacing: Theme.Spacing.sm) {
                let disabled = model.aiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                AppButton(title: "Save key", kind: .primary) { model.saveAIKey() }
                    .disabled(disabled)
                    .opacity(disabled ? 0.5 : 1)
                AppButton(title: "Add later", kind: .secondary) { advance(model) }
            }

        case .goals:
            AppButton(title: "Finish", kind: .primary) { finish(model) }
                .disabled(!model.goalsValid)
                .opacity(model.goalsValid ? 1 : 0.5)
        }
    }

    /// Advance one step inside the shared step spring (instant under Reduce Motion).
    private func advance(_ model: OnboardingModel) {
        withAnimation(reduceMotion ? nil : Theme.Motion.stepTransition) { model.advance() }
    }

    /// Go back one step inside the shared step spring (instant under Reduce Motion).
    private func back(_ model: OnboardingModel) {
        withAnimation(reduceMotion ? nil : Theme.Motion.stepTransition) { model.back() }
    }

    /// Build the profile + goals and finish. If the form is invalid, bounce back to the about-you
    /// step rather than fabricate data (never silent-write). On success, fire a haptic and either
    /// call the injected `onComplete` or persist onto the environment `AppModel`.
    private func finish(_ model: OnboardingModel) {
        guard let profile = model.buildProfile(), let goals = model.goals else {
            back(model)
            return
        }
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        if let onComplete {
            onComplete(profile, goals)
        } else {
            appModel.nutritionStore.setGoals(goals)
            appModel.foodLogSettings.setBias(model.calorieBias)
            appModel.completeOnboarding(profile)
            Task { await appModel.refreshLinks() }
        }
    }
}

private struct AboutYouStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.sm) {
                Txt("About you", variant: .title1)
                InfoDisclosure(
                    title: "Why we ask",
                    body: "We use these for your health reference ranges, and only on your own device. Your data stays on your phone; nothing here is shared."
                )
            }

            SegmentedPills(options: ["Female", "Male", "Other"], selection: sexBinding)

            SurfaceCard {
                VStack(spacing: Theme.Spacing.lg) {
                    StepperRow(label: "Age", unit: "yrs", value: $model.ageYears, range: 1...120)
                    HairlineDivider()
                    StepperRow(label: "Height", unit: "ft", value: $model.feet, range: 1...8)
                    HairlineDivider()
                    StepperRow(label: "Height", unit: "in", value: $model.inches, range: 0...11)
                    HairlineDivider()
                    // Read-only: WHOOP owns weight (a smart scale pushes to WHOOP). A stepper here
                    // would be overwritten by the first sync and imply an edit that does not stick.
                    HStack {
                        Txt("Weight", variant: .body, color: .labelSecondary)
                        Spacer(minLength: 0)
                        Txt("\(model.weightLb) lb", variant: .body, color: .label)
                    }
                }
            }

            Txt(
                model.weightFromWhoop
                    ? "Weight came from WHOOP. Step on your scale or change it in the WHOOP app and "
                        + "it updates here automatically."
                    : "WHOOP has no weight stored yet. Set it in the WHOOP app (or step on your "
                        + "scale) and Gains picks it up on the next sync.",
                variant: .footnote, color: .labelTertiary
            )
        }
    }

    /// Bridge the segmented pills' `Int` selection to the optional `Sex` model value.
    private var sexBinding: Binding<Int> {
        Binding(
            get: {
                switch model.sex {
                case .female: return 0
                case .male: return 1
                case .other: return 2
                case nil: return -1
                }
            },
            set: { idx in
                model.sex = [Sex.female, .male, .other][safe: idx]
            }
        )
    }
}

private struct StepperRow: View {
    let label: String
    let unit: String
    @Binding var value: Int
    var range: ClosedRange<Int> = 0...999
    var step: Int = 1

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Txt(label, variant: .bodyEmphasized)
                Txt(unit, variant: .footnote, color: .labelSecondary)
            }
            Spacer(minLength: 0)
            NumberStepper(value: $value, range: range, step: step, unit: unit)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value) \(unit)")
    }
}

private struct ConnectWhoopStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            StepHeader(
                icon: "waveform.path.ecg",
                title: "Connect Whoop",
                subtitle: "Sign in with your Whoop account to pull your recovery, sleep, and strain.",
                infoTitle: "Your credentials",
                infoBody: "Your credentials are used once to sign in and are never stored. You can connect later from Settings."
            )

            if model.whoopLinked {
                ConnectionStatusRow(
                    title: "Whoop connected", systemImage: "waveform.path.ecg",
                    state: .linked, hapticOnAppear: true
                )
            } else if model.whoopAwaitingMfa {
                SurfaceCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        Txt(
                            "Whoop sent a verification code. Enter it to finish connecting.",
                            variant: .subhead, color: .labelSecondary
                        )
                        FormField(
                            label: "Verification code", text: $model.whoopMfaCode,
                            placeholder: "6-digit code", keyboard: .numberPad
                        )
                    }
                }
            } else {
                SurfaceCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        FormField(
                            label: "Whoop email", text: $model.whoopEmail,
                            placeholder: "you@example.com", keyboard: .emailAddress
                        )
                        FormField(label: "Password", text: $model.whoopPassword, isSecure: true)
                    }
                }
            }

            if let error = model.whoopError {
                Txt(error, variant: .footnote, color: .danger)
            }
        }
    }
}

private struct ConnectAppleHealthStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                BrandLogo(.appleHealth, size: 48)
                    .accessibilityHidden(true)
                HStack(spacing: Theme.Spacing.sm) {
                    Txt("Connect Apple Health", variant: .title1)
                    InfoDisclosure(
                        title: "What we read",
                        body: "Reads your latest weight (e.g. from a scale that syncs to Apple Health). "
                            + "Nothing enters your record until you review and confirm it. You can "
                            + "connect later from Settings."
                    )
                }
                Txt(
                    "Sync your latest weight from Apple Health, for example from a smart scale.",
                    variant: .body, color: .labelSecondary
                )
            }

            if model.healthConnected {
                ConnectionStatusRow(
                    title: "Apple Health connected", systemImage: "heart.fill",
                    state: .linked, hapticOnAppear: true
                )
            } else if !model.healthAvailable {
                ConnectionStatusRow(
                    title: "Apple Health", systemImage: "heart.fill",
                    state: .unavailable("Not available on this device")
                )
            } else {
                SurfaceCard {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "scalemass")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.Colors.tint)
                            .frame(width: 30, height: 30)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Txt("Weight", variant: .bodyEmphasized)
                            Txt("Synced from Apple Health", variant: .footnote, color: .labelSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}

private struct AIKeyStep: View {
    @Bindable var model: OnboardingModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            StepHeader(
                icon: "sparkles",
                title: "Add your AI key",
                subtitle: "Gains uses your own OpenRouter key to estimate macros. Bring your own · Gains ships none.",
                infoTitle: "Storage and cost",
                infoBody: "Stored only on this device (encrypted keychain) and used solely to estimate macros. The full key is never shown again. You can add it later from Settings."
            )

            if model.aiKeySaved {
                ConnectionStatusRow(
                    title: "Key saved", systemImage: "key.fill",
                    state: .saved, hapticOnAppear: true
                )
            } else {
                SurfaceCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        FormField(
                            label: "OpenRouter API key", text: $model.aiKeyDraft,
                            placeholder: "sk-or-…", isSecure: true
                        )
                        AppButton(title: "Get a key", icon: "key.fill", kind: .tertiary) {
                            if let url = URL(string: "https://openrouter.ai/keys") { openURL(url) }
                        }
                    }
                }
            }

            InsightCard(
                icon: "creditcard",
                title: "About cost",
                message: "Add about $10 of OpenRouter credit · that's months of logging. You only pay for what you use, and can see your spend anytime. New restaurant or brand foods cost about half a cent each (web search); everything you eat regularly is free after the first time.",
                accent: Theme.Colors.tint
            )
        }
    }
}

private struct GoalsStep: View {
    @Bindable var model: OnboardingModel
    /// Profile from the about-you step, driving the "Help me" calculator. `nil` if that step is
    /// incomplete.
    let profile: Profile?

    @State private var showCalculator = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack {
                Txt("Your goals", variant: .title1)
                Spacer(minLength: 0)
                AppButton(title: "Help me", icon: "sparkles", kind: .tertiary) { showCalculator = true }
                    .fixedSize()
                    .accessibilityLabel("Help me set my goal")
            }

            Txt(
                "Set your daily targets. Tap the sparkles for an estimate, then edit anything and finish.",
                variant: .body, color: .labelSecondary
            )

            SurfaceCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    HStack {
                        Txt("Daily calories", variant: .bodyEmphasized)
                        Spacer(minLength: 0)
                        Txt("your headline target", variant: .footnote, color: .labelTertiary)
                    }
                    HStack {
                        Spacer(minLength: 0)
                        NumberStepper(value: $model.calorieGoal, range: 0...6000, step: 50, unit: "kcal")
                            .contentTransition(.numericText())
                        Spacer(minLength: 0)
                    }
                    MacroSplitBar(
                        proteinG: model.proteinGoal,
                        fatG: model.fatGoal,
                        carbsG: model.carbGoal
                    )
                }
            }

            SurfaceCard {
                VStack(spacing: Theme.Spacing.lg) {
                    MacroStepperRow(
                        title: "Protein", color: Theme.Chart.protein,
                        why: "Builds and preserves muscle; the most satiating macro.",
                        value: $model.proteinGoal
                    )
                    HairlineDivider()
                    MacroStepperRow(
                        title: "Fat", color: Theme.Chart.fat,
                        why: "Supports hormones and absorbs vitamins.",
                        value: $model.fatGoal
                    )
                    HairlineDivider()
                    MacroStepperRow(
                        title: "Carbs", color: Theme.Chart.carbs,
                        why: "Your main fuel for training and daily energy.",
                        value: $model.carbGoal
                    )
                }
            }

            SurfaceCard {
                MacroStepperRow(
                    title: "Daily steps", color: Theme.Chart.activity,
                    why: "A simple daily movement target; progress comes from your day's step count.",
                    value: $model.stepsGoal,
                    icon: "figure.walk",
                    range: 0...50_000, step: 1_000, unit: "steps",
                    accessibilityUnit: "steps"
                )
            }

            CalorieBiasCard(selection: $model.calorieBias)

            Txt(
                "Goals are targets you set.",
                variant: .footnote, color: .labelTertiary, center: true
            )
        }
        .sheet(isPresented: $showCalculator) {
            GoalCalculatorSheet(profile: profile) { result in
                model.applyEstimate(result)
                showCalculator = false
            }
        }
    }
}

/// Calorie-estimation bias selector for the goals step. Each row is a selectable title + description;
/// the selected row shows a filled check.
private struct CalorieBiasCard: View {
    @Binding var selection: CalorieBias

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack {
                    Txt("Calorie estimate bias", variant: .bodyEmphasized)
                    Spacer(minLength: 0)
                    Txt("how estimates lean", variant: .footnote, color: .labelTertiary)
                }
                VStack(spacing: 0) {
                    ForEach(Array(CalorieBias.allCases.enumerated()), id: \.element) { index, bias in
                        Button { selection = bias } label: { row(bias) }
                            .buttonStyle(.plain)
                        if index < CalorieBias.allCases.count - 1 { HairlineDivider() }
                    }
                }
                Txt(selection.disclosure, variant: .footnote, color: .labelTertiary)
            }
        }
    }

    private func row(_ bias: CalorieBias) -> some View {
        let selected = bias == selection
        return HStack(alignment: .top, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Txt(bias.title, variant: .bodyEmphasized)
                Txt(bias.pickerDescription, variant: .footnote, color: .labelSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(selected ? Theme.Colors.tint : Theme.Colors.borderStrong)
        }
        .padding(.vertical, Theme.Spacing.md)
        .contentShape(.rect)
    }
}

private struct MacroStepperRow: View {
    let title: String
    let color: Color
    let why: String
    @Binding var value: Int
    /// SF Symbol shown in place of the color dot (used by the steps row). `nil` → color dot.
    var icon: String? = nil
    var range: ClosedRange<Int> = 0...600
    var step: Int = 1
    var unit: String = "g"
    /// Spoken units for VoiceOver (the gram rows say "grams per day"; steps says "steps per day").
    var accessibilityUnit: String = "grams"

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.sm) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(color)
                            .frame(width: 10)
                    } else {
                        Circle().fill(color).frame(width: 10, height: 10)
                    }
                    Txt(title, variant: .bodyEmphasized)
                }
                Txt(why, variant: .footnote, color: .labelTertiary)
            }
            Spacer(minLength: 0)
            NumberStepper(value: $value, range: range, step: step, unit: unit)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value) \(accessibilityUnit) per day")
    }
}

private struct StepHeader: View {
    let icon: String
    let title: String
    let subtitle: String
    var infoTitle: String? = nil
    var infoBody: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.Colors.tint)
                .frame(width: 48, height: 48)
                .background(Theme.Colors.tintSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                .accessibilityHidden(true)
            HStack(spacing: Theme.Spacing.sm) {
                Txt(title, variant: .title1)
                if let infoBody {
                    InfoDisclosure(title: infoTitle, body: infoBody)
                }
            }
            Txt(subtitle, variant: .body, color: .labelSecondary)
        }
    }
}

#if DEBUG
#Preview("Onboarding") {
    OnboardingFlow { _, _ in }
        .environment(AppModel.sample)
}
#endif
