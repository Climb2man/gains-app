import SwiftUI

/// Weight trend, sourced entirely from WHOOP.
///
/// There is deliberately NO manual entry here. A smart scale pushes to WHOOP, `AppModel`'s
/// `syncWeightFromWhoop()` reads WHOOP's stored measurement and logs the weigh-in. To correct a
/// weight you change it in WHOOP and re-sync. (Apple Health was the original path but HealthKit
/// cannot be provisioned on a free Apple ID, so it is gone.)
struct WeightTrendCard: View {
    @Environment(AppModel.self) private var appModel
    @State private var syncing = false

    /// The window the chart + delta cover.
    private let windowDays = 90

    private var series: [Double] { appModel.weightStore.historyLb(days: windowDays) }
    private var latest: Double? { appModel.weightStore.latestLb }
    private var change: Double? { appModel.weightStore.changeLb(days: windowDays) }

    var body: some View {
        Card(metricAccent: Theme.Chart.sleep) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.sm) {
                    CardHeader(title: "WEIGHT", icon: "scalemass.fill")
                    Spacer(minLength: 0)
                    if appModel.whoopLinked {
                        syncButton
                    }
                }

                if let latest {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                        Text(Format.oneDecimal(latest))
                            .font(Theme.Font.statNumber)
                            .foregroundStyle(Theme.Colors.label)
                        Txt("lb", variant: .footnote, color: .labelTertiary)
                        if let change, abs(change) >= 0.05 {
                            changePill(change)
                        }
                        Spacer(minLength: 0)
                        Txt("last \(windowDays / 30) mo", variant: .footnote, color: .labelTertiary)
                    }

                    if series.count >= 2 {
                        GeometryReader { geo in
                            TrendChart(
                                points: series,
                                color: Theme.Chart.sleep,
                                height: 120,
                                width: geo.size.width
                            )
                        }
                        .frame(height: 120)
                    } else {
                        Txt("Weigh in a few more times and your trend appears here.",
                            variant: .footnote, color: .labelTertiary)
                    }

                    sourceFooter
                } else {
                    emptyState
                }
            }
        }
        .task {
            // Pick up a scale push made since the app was last open.
            await appModel.syncWeightFromWhoop()
        }
    }

    private var syncButton: some View {
        Button {
            guard !syncing else { return }
            syncing = true
            Task {
                await appModel.syncWeightFromWhoop()
                syncing = false
            }
        } label: {
            if syncing {
                ProgressView().controlSize(.small)
            } else {
                Label("Sync", systemImage: "arrow.clockwise")
                    .font(Theme.Font.footnote.weight(.semibold))
            }
        }
        .buttonStyle(.bordered)
        .tint(Theme.Chart.sleep)
        .disabled(syncing)
    }

    /// Names the source, so a number that looks wrong points at where to fix it: WHOOP, not here.
    private var sourceFooter: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 10))
            if let synced = appModel.lastWhoopWeightSync {
                Txt("From WHOOP · \(synced.formatted(date: .omitted, time: .shortened))",
                    variant: .footnote, color: .labelTertiary)
            } else {
                Txt("From WHOOP", variant: .footnote, color: .labelTertiary)
            }
        }
        .foregroundStyle(Theme.Colors.labelTertiary)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Txt("No weigh-ins yet.", variant: .body, color: .labelSecondary)
            if appModel.whoopLinked {
                Txt("Weight comes from WHOOP. Step on your scale, or set it in the WHOOP app, then sync.",
                    variant: .footnote, color: .labelTertiary)
                Button {
                    guard !syncing else { return }
                    syncing = true
                    Task {
                        await appModel.syncWeightFromWhoop()
                        syncing = false
                    }
                } label: {
                    Label("Sync from WHOOP", systemImage: "arrow.clockwise")
                        .font(Theme.Font.footnote.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Chart.sleep)
                .disabled(syncing)
            } else {
                Txt("Connect WHOOP in Settings to track your weight.",
                    variant: .footnote, color: .labelTertiary)
            }
        }
    }

    /// Small up/down pill: shows the change as an arrow + lb, never judged as good or bad.
    private func changePill(_ delta: Double) -> some View {
        let down = delta < 0
        return HStack(spacing: 2) {
            Image(systemName: down ? "arrow.down" : "arrow.up")
                .font(.system(size: 10, weight: .bold))
            Text("\(Format.oneDecimal(abs(delta))) lb")
                .font(Theme.Font.footnote.weight(.semibold))
        }
        .foregroundStyle(Theme.Colors.labelSecondary)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 3)
        .background(Capsule().fill(Theme.Colors.fieldBackground))
    }
}
