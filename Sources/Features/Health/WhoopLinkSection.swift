import SwiftUI

@MainActor
@Observable
final class WhoopLinkModel {
    enum Status: Equatable { case none, info(String), error(String) }

    private(set) var linked: Bool
    var email = ""
    var password = ""
    var code = ""
    private(set) var busy = false
    private(set) var status: Status = .none
    /// Set when Whoop demands an MFA code; the password field is replaced by a code field.
    private(set) var mfa: WhoopMfaHandle?

    private let whoop: any WhoopService
    private let onLinkChange: () -> Void

    init(whoop: any WhoopService, linked: Bool, onLinkChange: @escaping () -> Void) {
        self.whoop = whoop
        self.linked = linked
        self.onLinkChange = onLinkChange
    }

    /// Re-sync from resolved session state: the init seed is point-in-time, so a link made
    /// elsewhere (e.g. onboarding) reflects here without recreating the model.
    func syncLinked(_ linked: Bool) {
        self.linked = linked
    }

    func login() async {
        guard !email.trimmed.isEmpty, !password.isEmpty else { return }
        busy = true; status = .none
        defer { busy = false }
        switch await whoop.login(email: email.trimmed, password: password) {
        case .ok:
            onLinked()
        case let .mfa(handle):
            password = ""
            mfa = handle
            status = .info("Enter the verification code Whoop just sent you.")
        case .failed:
            status = .error("Couldn't sign in. Check your Whoop email and password.")
        }
    }

    func submitMfa() async {
        guard let mfa, !code.trimmed.isEmpty else { return }
        busy = true; status = .none
        defer { busy = false }
        if await whoop.submitMfa(code: code.trimmed, handle: mfa) {
            onLinked()
        } else {
            status = .error("That code didn't work. Try signing in again.")
        }
    }

    func cancelMfa() {
        mfa = nil; code = ""; status = .none
    }

    func disconnect() async {
        busy = true
        defer { busy = false }
        await whoop.clear()
        linked = false
        onLinkChange()
    }

    private func onLinked() {
        linked = true
        email = ""; password = ""; code = ""; mfa = nil; status = .none
        onLinkChange()
    }
}

@MainActor
struct WhoopLinkSection: View {
    @State private var model: WhoopLinkModel

    init(model: WhoopLinkModel) {
        _model = State(initialValue: model)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var model = model
        return SurfaceCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.md) {
                    BrandLogo(.whoop, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Txt("Whoop", variant: .bodyEmphasized)
                        Txt("Private link, your own account", variant: .footnote, color: .labelSecondary)
                    }
                    Spacer(minLength: Theme.Spacing.sm)
                    InfoDisclosure(
                        title: "About this Whoop link",
                        body: "Uses Whoop's unofficial API with your own login. Your password is sent "
                            + "only to Whoop to sign in; only the resulting tokens are kept on this device "
                            + "(encrypted). This is outside Whoop's official developer terms and may break "
                            + "without notice."
                    )
                }

                Group {
                    if model.linked {
                        linkedState
                    } else if model.mfa != nil {
                        mfaForm($model)
                            .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                    } else {
                        loginForm($model)
                    }
                }
                .animation(reduceMotion ? nil : Theme.Motion.stepTransition, value: model.mfa != nil)

                switch model.status {
                case .none:
                    EmptyView()
                case let .info(text):
                    Txt(text, variant: .footnote, color: .labelSecondary)
                case let .error(text):
                    Txt(text, variant: .footnote, color: .danger)
                }
            }
        }
    }

    private var linkedState: some View {
        VStack(spacing: Theme.Spacing.md) {
            ConnectionStatusRow(
                title: "Linked on this device",
                systemImage: "waveform.path.ecg",
                state: .linked
            )
            AppButton(
                title: model.busy ? "Disconnecting…" : "Disconnect",
                kind: .tertiary
            ) { Task { await model.disconnect() } }
            .foregroundStyle(Theme.Colors.danger)
            .disabled(model.busy)
        }
    }

    private func mfaForm(_ model: Bindable<WhoopLinkModel>) -> some View {
        let m = model.wrappedValue
        return VStack(spacing: Theme.Spacing.md) {
            FormField(
                label: "Verification code",
                text: model.code,
                placeholder: "6-digit code",
                keyboard: .numberPad
            )
            AppButton(
                title: m.busy ? "Verifying…" : "Verify code",
                kind: .primary
            ) { Task { await m.submitMfa() } }
            .disabled(m.busy || m.code.trimmed.isEmpty)

            Button { m.cancelMfa() } label: {
                Txt("Use a different login", variant: .footnote, color: .labelSecondary, center: true)
            }
            .buttonStyle(.plain)
            .padding(.vertical, Theme.Spacing.sm)
        }
    }

    private func loginForm(_ model: Bindable<WhoopLinkModel>) -> some View {
        let m = model.wrappedValue
        return VStack(spacing: Theme.Spacing.md) {
            FormField(
                label: "Whoop email",
                text: model.email,
                placeholder: "you@example.com",
                keyboard: .emailAddress,
                autocap: .never
            )
            FormField(
                label: "Whoop password",
                text: model.password,
                placeholder: "Your Whoop password",
                isSecure: true
            )
            AppButton(
                title: m.busy ? "Signing in…" : "Link Whoop",
                kind: .primary
            ) { Task { await m.login() } }
            .disabled(m.busy || m.email.trimmed.isEmpty || m.password.isEmpty)
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
