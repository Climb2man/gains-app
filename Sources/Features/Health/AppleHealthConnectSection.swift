import SwiftUI

@MainActor
struct AppleHealthConnectSection: View {
    @Environment(AppModel.self) private var appModel

    @State private var available = false
    @State private var requested = false
    @State private var busy = false
    /// The weight (kg) read from Apple Health, awaiting user confirmation before it enters the record. nil → nothing pending.
    @State private var pendingWeightKg: Double?
    @State private var showNoData = false
    /// Persisted, non-PHI: the user connected Health at least once. While set, every visit re-reads the
    /// latest weight and offers any new reading for confirmation; import still needs the user's tap.
    @AppStorage(AppleHealthKeys.weightRequested) private var weightRequested = false
    /// Persisted, non-PHI: a weight read actually returned data. HealthKit can't confirm read access
    /// otherwise, so only this justifies the green "Connected" surface. Set on the first successful
    /// read; cleared on Disconnect.
    @AppStorage(AppleHealthKeys.weightConnected) private var weightConnected = false
    /// The last weight offered this session, so declining ("Not now") isn't re-asked on every visit
    /// until the scale reports a different value.
    @State private var lastOfferedKg: Double?

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.md) {
                    BrandLogo(.appleHealth, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Txt("Apple Health", variant: .bodyEmphasized)
                        Txt("Latest weight", variant: .footnote, color: .labelSecondary)
                    }
                    Spacer(minLength: Theme.Spacing.sm)
                    InfoDisclosure(
                        title: "Apple Health",
                        body: "Reads your latest weight (e.g. from a Renpho scale that syncs to Apple "
                            + "Health). Nothing enters your record until you review and confirm it."
                    )
                }

                ConnectionStatusRow(
                    title: "Weight",
                    systemImage: "scalemass",
                    state: connectionState
                )

                if weightRequested || weightConnected {
                    AppButton(title: "Disconnect", kind: .tertiary, action: disconnect)
                }
            }
        }
        .onAppear {
            available = appModel.health.isAvailable()
            if weightRequested { requested = true }
            guard available, weightRequested, !busy else { return }
            Task {
                guard let kg = await appModel.health.latestWeightKg() else { return }
                weightConnected = true
                await appModel.importHealthWeightHistory()
                let current = appModel.profile?.weightKg ?? 0
                guard abs(kg - current) >= 0.05, kg != lastOfferedKg else { return }
                lastOfferedKg = kg
                pendingWeightKg = kg
            }
        }
        .alert("Import weight from Apple Health?", isPresented: importPresented, presenting: pendingWeightKg) { _ in
            Button("Use it") { if let kg = pendingWeightKg { applyWeight(kg) } }
            Button("Not now", role: .cancel) {}
        } message: { kg in
            Text("Apple Health's latest weight is \(Format.weightLb(kg)). Save it to your profile?")
        }
        .alert("No weight found", isPresented: $showNoData) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Apple Health didn't return a weight reading. Add one (or sync your scale), then tap Connect again.")
        }
    }

    private var importPresented: Binding<Bool> {
        Binding(get: { pendingWeightKg != nil }, set: { if !$0 { pendingWeightKg = nil } })
    }

    /// Connection state. A requested-but-unconfirmed read permission stays neutral (`.requested`);
    /// only once a weight actually reads back (`weightConnected`) do we show "Connected" (`.linked`).
    private var connectionState: ConnectionStatusRow.State {
        if !available {
            return .unavailable("Not available on this device")
        }
        if weightConnected {
            return .linked
        }
        if requested {
            return .requested
        }
        return .connect(label: busy ? "…" : "Connect", action: connect)
    }

    private func connect() {
        guard available, !busy else { return }
        busy = true
        Task {
            await appModel.health.requestAuthorization()
            let weight = await appModel.health.latestWeightKg()
            busy = false
            requested = true
            weightRequested = true
            if let weight {
                weightConnected = true
                await appModel.importHealthWeightHistory()
                lastOfferedKg = weight
                pendingWeightKg = weight
            } else {
                showNoData = true
            }
        }
    }

    /// Forget the connection locally: clear the persisted flags so passive re-reads stop and the row
    /// reverts to "Connect." (Read access itself can only be revoked in iOS Settings → Privacy → Health.)
    private func disconnect() {
        requested = false
        weightRequested = false
        weightConnected = false
        lastOfferedKg = nil
        pendingWeightKg = nil
    }

    /// Write the confirmed weight to the record. Only called after the user reviews and taps "Use it":
    /// imported values are user-confirmed before they become canonical.
    private func applyWeight(_ kg: Double) {
        guard var profile = appModel.profile else { return }
        profile.weightKg = kg
        appModel.updateProfile(profile)
    }
}

#if DEBUG
#Preview {
    ScrollView {
        AppleHealthConnectSection()
            .padding()
            .environment(AppModel.sample)
    }
    .background(Theme.Colors.background)
}
#endif
