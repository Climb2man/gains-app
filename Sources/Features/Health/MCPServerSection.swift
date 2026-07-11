import SwiftUI

struct MCPServerSection: View {
    @Environment(AppModel.self) private var appModel
    @State private var copied = false
    @State private var showWipeConfirm = false

    private var sync: GainsMCPSync { appModel.mcpSync }

    private var enabled: Binding<Bool> {
        Binding(get: { sync.isEnabled }, set: { sync.setEnabled($0) })
    }

    private var serverURL: Binding<String> {
        Binding(get: { sync.serverURLString }, set: { sync.setServerURL($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionCaption(title: "AI Connector (MCP)")
            SurfaceCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Toggle(isOn: enabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Txt("Connect my data to your assistant", variant: .bodyEmphasized)
                            Txt("Read-only · syncs to your own server", variant: .footnote, color: .labelTertiary)
                        }
                    }
                    .tint(Theme.Colors.tint)

                    if sync.isEnabled {
                        configFields
                        if sync.isConfigured { connectorRow; statusRow }
                        wipeButton
                    }

                    Txt(
                        "When ON, a minimized, read-only copy of your logged data (food, workouts, "
                            + "Whoop, profile) is sent to the server URL you enter, so your MCP client (web or "
                            + "mobile) can read it. Nothing can be changed through it, and your keys are "
                            + "never sent. Use “Disconnect & wipe” to erase the server's copy.",
                        variant: .footnote, color: .labelTertiary
                    )
                }
            }
        }
        .onChange(of: sync.connectorURLString) { copied = false }
    }

    private var configFields: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            field {
                TextField("https://your-server.fly.dev", text: serverURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.system(.footnote, design: .monospaced))
            }
            field {
                HStack {
                    SecureField(sync.hasToken ? "Sync token saved, tap to replace" : "Sync token", text: $tokenDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.footnote, design: .monospaced))
                        .onSubmit { commitToken() }
                    if !tokenDraft.isEmpty {
                        Button("Save") { commitToken() }
                            .font(Theme.Font.footnote)
                            .buttonStyle(.bordered)
                            .tint(Theme.Colors.tint)
                    }
                }
            }
        }
    }

    private var connectorRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Txt("Add this URL in your MCP client → Connectors", variant: .footnote, color: .labelTertiary)
                Text(sync.connectorURLString)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Theme.Colors.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            Button(copied ? "Copied" : "Copy") {
                UIPasteboard.general.string = sync.connectorURLString
                copied = true
            }
            .font(Theme.Font.footnote)
            .buttonStyle(.bordered)
            .tint(Theme.Colors.tint)
        }
        .padding(Theme.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.Colors.fieldBackground))
    }

    private var statusRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if sync.isSyncing {
                ProgressView().controlSize(.small)
                Txt("Syncing…", variant: .footnote, color: .labelSecondary)
            } else if let error = sync.lastError {
                Txt(error, variant: .footnote, color: .labelSecondary)
            } else if let at = sync.lastSyncedAt {
                Txt("Synced \(at.formatted(.relative(presentation: .named)))"
                    + (sync.lastSummary.map { " · \($0)" } ?? ""),
                    variant: .footnote, color: .labelTertiary)
            } else {
                Txt("Not synced yet", variant: .footnote, color: .labelTertiary)
            }
            Spacer(minLength: 0)
            Button("Sync now") { Task { await sync.syncNow() } }
                .font(Theme.Font.footnote)
                .buttonStyle(.bordered)
                .tint(Theme.Colors.tint)
                .disabled(sync.isSyncing)
        }
    }

    private var wipeButton: some View {
        Button(role: .destructive) { showWipeConfirm = true } label: {
            Txt("Disconnect & wipe server copy", variant: .footnote, color: .labelSecondary)
        }
        .confirmationDialog("Disconnect and erase the server's copy of your data?",
                            isPresented: $showWipeConfirm, titleVisibility: .visible) {
            Button("Disconnect & wipe", role: .destructive) {
                tokenDraft = ""
                Task { await sync.wipeRemote() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @State private var tokenDraft = ""

    private func commitToken() {
        sync.setToken(tokenDraft)
        tokenDraft = ""
        if sync.isConfigured { Task { await sync.syncNow() } }
    }

    private func field<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(Theme.Spacing.sm)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.Colors.fieldBackground))
    }
}

#if DEBUG
#Preview {
    ScrollView {
        MCPServerSection()
            .padding()
            .environment(AppModel.sample)
    }
    .background(Theme.Colors.background)
}
#endif
