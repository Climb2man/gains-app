import SwiftUI

@MainActor
struct OpenRouterKeySection: View {
    @Environment(AppModel.self) private var appModel

    @State private var hasKey: Bool
    @State private var draft = ""

    init(hasKey: Bool = false) {
        _hasKey = State(initialValue: hasKey)
    }

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.md) {
                    BrandLogo(.openRouter, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Txt("AI key", variant: .bodyEmphasized)
                        Txt("OpenRouter, bring your own", variant: .footnote, color: .labelSecondary)
                    }
                    Spacer(minLength: Theme.Spacing.sm)
                    InfoDisclosure(
                        title: "About your AI key",
                        body: "Stored only on this device (encrypted Keychain). Used solely to estimate "
                            + "macros, sent only to OpenRouter. Each person uses their own key, so Gains "
                            + "ships none. The full key is never shown again."
                    )
                }

                if hasKey {
                    ConnectionStatusRow(
                        title: "Key saved · sk-or-••••••••",
                        systemImage: "key.horizontal.fill",
                        state: .saved
                    )
                    AppButton(title: "Remove key", kind: .tertiary) { removeKey() }
                        .foregroundStyle(Theme.Colors.danger)
                } else {
                    FormField(
                        label: "OpenRouter API key",
                        text: $draft,
                        placeholder: "Paste your OpenRouter API key"
                    )
                    AppButton(title: "Save key", kind: .primary) { saveKey() }
                        .disabled(draft.trimmedIsEmpty)
                }
            }
        }
        .onAppear { hasKey = appModel.aiKeyStore.hasKey }
    }

    private func saveKey() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if appModel.aiKeyStore.save(trimmed) {
            hasKey = true
            draft = ""
            Task { await appModel.refreshLinks() }
        }
    }

    private func removeKey() {
        appModel.aiKeyStore.clear()
        hasKey = false
        draft = ""
        Task { await appModel.refreshLinks() }
    }
}

private extension String {
    var trimmedIsEmpty: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

#if DEBUG
#Preview {
    ScrollView {
        OpenRouterKeySection(hasKey: true)
            .padding()
            .environment(AppModel.sample)
    }
    .background(Theme.Colors.background)
}
#endif
