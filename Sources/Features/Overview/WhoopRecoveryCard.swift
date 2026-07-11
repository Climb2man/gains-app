import SwiftUI

struct WhoopRecoveryCard: View {
    /// The selected day's Whoop snapshot, or nil when not linked or the day has no usable data.
    let summary: WhoopSummary?
    /// The selected day key (YYYY-MM-DD); scopes each wheel's detail-screen route.
    var day: String = ""
    /// True during the initial or per-date load; shows "checking…" instead of the no-data state.
    var loading: Bool = false
    /// Whether the selected day is today; switches the title and tunes the empty state.
    var isToday: Bool = true
    /// Short label for the selected day (e.g. "Mon"), used in the past-day title and empty copy.
    var dayLabel: String?
    /// Deep-links into the Recovery tab; also drives the connect CTA in the empty state.
    var onPress: (() -> Void)?

    private let strainMax = 21.0

    private var pct: Double? { summary?.recoveryPct }
    private var hasRecovery: Bool { pct != nil }

    var body: some View {
        if hasRecovery, let pct {
            populated(pct: pct)
        } else {
            emptyState
        }
    }

    private func populated(pct: Double) -> some View {
        VStack(spacing: Theme.Spacing.xl) {
            wheelRow(wheels(pct: pct))
            vitals
            InsightCard(
                icon: "bolt.heart",
                title: "Your recovery today",
                message: Self.recoveryFraming(pct),
                accent: Theme.Chart.recovery
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func wheelRow(_ ws: [Wheel]) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            ForEach(ws) { wheel in
                NavigationLink(value: wheel.route) {
                    wheelView(wheel)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func wheelView(_ wheel: Wheel) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            RingChart(progress: wheel.progress, size: 98, strokeWidth: 10, color: wheel.accent) {
                Text(wheel.centerValue)
                    .font(Theme.Font.number(size: 22, weight: .bold))
                    .foregroundStyle(Theme.Colors.label)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Text(wheel.name)
                .font(Theme.Font.footnote.weight(.medium))
                .foregroundStyle(Theme.Colors.labelSecondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .accessibilityElement()
        .accessibilityLabel("\(wheel.name) \(wheel.centerValue)")
        .accessibilityHint("Opens \(wheel.name) detail")
    }

    private func wheels(pct: Double) -> [Wheel] {
        var result = [
            Wheel(name: "Recovery", progress: pct / 100, centerValue: "\(Int(pct.rounded()))%",
                  accent: Theme.Chart.recovery, route: .recovery(day: day)),
        ]
        if let strain = summary?.dayStrain {
            result.append(Wheel(name: "Strain", progress: min(1, strain / strainMax),
                                 centerValue: Format.oneDecimal(strain),
                                 accent: Theme.Chart.strain, route: .strain(day: day)))
        }
        if let sleep = summary?.sleepHours {
            result.append(Wheel(name: "Sleep", progress: min(1, sleep / 8),
                                 centerValue: "\(Format.oneDecimal(sleep))h",
                                 accent: Theme.Chart.sleep, route: .sleep(day: day)))
        }
        return result
    }

    /// One hero wheel: a ring metric + the detail route it opens on tap.
    private struct Wheel: Identifiable {
        let name: String
        let progress: Double
        let centerValue: String
        let accent: Color
        let route: WhoopRoute
        var id: String { name }
    }

    private var vitals: some View {
        HStack(spacing: Theme.Spacing.md) {
            FloatingStatCard(
                icon: "waveform.path.ecg", title: "HRV",
                value: summary?.hrvMs.map { Format.int($0) } ?? "–",
                unit: summary?.hrvMs != nil ? "ms" : nil,
                trend: Self.trend(value: summary?.hrvMs, baseline: summary?.hrvBaselineMs),
                trendColor: Theme.Colors.tint, accent: Theme.Chart.heartrate, glass: false
            )
            FloatingStatCard(
                icon: "heart.fill", title: "Resting HR",
                value: summary?.rhrBpm.map { Format.int($0) } ?? "–",
                unit: summary?.rhrBpm != nil ? "bpm" : nil,
                trend: Self.trend(value: summary?.rhrBpm, baseline: summary?.rhrBaselineBpm),
                trendColor: Theme.Colors.tint, accent: Theme.Chart.heartrate, glass: false
            )
        }
    }

    static func trend(value: Double?, baseline: Double?) -> MetricCard.Trend {
        guard let value, let baseline, baseline > 0 else { return .none }
        let delta = (value - baseline) / baseline
        if delta > 0.02 { return .up }
        if delta < -0.02 { return .down }
        return .none
    }

    private var emptyState: some View {
        let pastNoData = !loading && !isToday
        let heading: String
        let detail: String
        if loading {
            heading = "Checking Whoop…"
            detail = "Loading your recovery, HRV, resting HR, and sleep."
        } else if pastNoData {
            heading = "No Whoop data for this day"
            detail = dayLabel.map { "Whoop didn't record \($0)." } ?? "Whoop didn't record this day."
        } else {
            heading = "Connect Whoop"
            detail = "Link Whoop in Settings to see your daily recovery here."
        }
        let showLink = !loading && !pastNoData && onPress != nil

        return HStack(spacing: Theme.Spacing.lg) {
            ZStack {
                Circle().fill(Theme.Chart.recovery.opacity(0.12))
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.Chart.recovery)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(heading)
                    .font(Theme.Font.bodyEmphasized)
                    .foregroundStyle(Theme.Colors.label)
                Text(detail)
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Colors.labelSecondary)
                if showLink {
                    Button(action: { onPress?() }) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "link").font(.system(size: 13))
                            Text("Open Whoop").font(Theme.Font.footnote.weight(.semibold))
                        }
                        .foregroundStyle(Theme.Colors.tint)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    static func recoveryFraming(_ pct: Double) -> String {
        if pct >= 67 { return "Your recovery is reading higher than your own typical day right now." }
        if pct >= 34 { return "Your recovery is sitting around your own typical day right now." }
        return "Your recovery is reading lower than your own typical day right now."
    }
}
