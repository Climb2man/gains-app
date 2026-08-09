import SwiftUI

struct OverviewScreen: View {
    /// Tab-router hook: the settings gear switches to the Health tab (profile, units, connections).
    /// nil in previews disables the gear.
    var onOpenSettings: (() -> Void)?
    @Environment(AppModel.self) private var appModel
    @State private var model: OverviewModel?
    /// Pushes the notes journal (the header's notebook button) for the selected day.
    @State private var showJournal = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let model {
                    content(model)
                }
            }
            .background(Theme.Colors.background)
            .navigationDestination(for: WhoopRoute.self) { route in
                switch route {
                case .recovery(let day): RecoveryDetailScreen(date: day)
                case .strain(let day): StrainDetailScreen(date: day)
                case .sleep(let day): SleepDetailScreen(date: day)
                case .stress(let day): StressDetailScreen(date: day)
                case .insights: InsightsScreen()
                case .compare: CompareScreen()
                case .explore: ExploreScreen()
                }
            }
            .navigationDestination(isPresented: $showJournal) {
                JournalScreen(store: appModel.journal, day: model?.selectedDayKey)
            }
            .suppressRootBackSwipe()
        }
        .task {
            if model == nil { model = OverviewModel(appModel: appModel) }
        }
        .task(id: model?.selectedDayKey) {
            await model?.loadWhoopSummary()
        }
        .onChange(of: appModel.selectedDate) { _, date in
            // The shell resets `selectedDate` to today when the scene becomes active (GainsApp), but the
            // model only reads it in `init`, which runs once. Without this the screen stays on the day
            // it was built for: suspend overnight, reopen, and Overview still shows yesterday.
            model?.selectedDayKey = DateStrip.toKey(date)
        }
    }

    @ViewBuilder
    private func content(_ model: OverviewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            heroZone(model)

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                MetricScroll(items: model.metrics)

                EnergyBalanceCard(
                    totals: model.dayTotals,
                    summary: model.whoopSummary,
                    profile: model.profile,
                    title: model.isToday ? "ENERGY BALANCE" : "ENERGY BALANCE · \(model.shortDayLabel.uppercased())"
                )

                if let goalPace = model.goalPace {
                    GoalPaceCard(state: goalPace)
                }

                StreakAdherenceCard(
                    streak: model.currentStreak,
                    longestStreak: model.longestStreak,
                    weekHits: model.weekHits
                )

                MacroDonutCard(
                    totals: model.dayTotals,
                    title: model.isToday ? "MACROS" : "MACROS · \(model.shortDayLabel.uppercased())"
                )

                WeightTrendCard()

                if model.usesSampleData {
                    RecoveryTrendCard(
                        points: model.recoveryTrendValues,
                        labels: model.recoveryTrendLabels,
                        latestLabel: model.recoveryTrendLatest,
                        average: model.recoveryTrendAverage,
                        typicalLow: model.recoveryTypicalLow,
                        typicalHigh: model.recoveryTypicalHigh
                    )
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionHeader(title: "Your health score")
                ComingSoonCard(
                    title: "Biological age",
                    description: "A single view of how your body is tracking. It arrives once your labs are connected."
                )
                UnifyHealthCard()
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.lg)
        }
        .padding(.bottom, 96)
    }

    @ViewBuilder
    private func heroZone(_ model: OverviewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            DashboardHeader(
                name: model.profileName,
                onOpenSettings: onOpenSettings,
                onOpenJournal: { showJournal = true }
            )

            DateStrip(
                selectedDate: model.selectedDayKey,
                onSelectDate: { model.selectedDayKey = $0 },
                days: DateStrip.trailingYear,
                adherenceByDay: model.adherenceByDay
            )

            // Calories left is the first card, above recovery. It sits INSIDE the hero zone and
            // below the date strip on purpose: the number is scoped to the selected day, so the
            // day picker has to come first or the ring would change without visible cause.
            CaloriesRemainingCard(
                totals: model.dayTotals,
                goals: model.goals,
                title: model.isToday ? "CALORIES LEFT" : "CALORIES LEFT · \(model.shortDayLabel.uppercased())"
            )

            WhoopRecoveryCard(
                summary: model.whoopSummary,
                loading: false,
                isToday: model.isToday,
                dayLabel: model.shortDayLabel
            )
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.sm)
    }
}

/// A plain title above a secondary section (e.g. "Your health score").
struct SectionHeader: View {
    let title: String
    var body: some View {
        Txt(title, variant: .title2)
            .padding(.horizontal, Theme.Spacing.xs)
    }
}

/// Placeholder card for a feature that arrives later (the biological-age teaser).
/// No fabricated number, no claim.
struct ComingSoonCard: View {
    let title: String
    let description: String

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Colors.tint)
                    Txt(title, variant: .bodyEmphasized)
                    Spacer(minLength: 0)
                    Pill(text: "Soon", tone: .tint)
                }
                Txt(description, variant: .footnote, color: .labelSecondary)
            }
        }
    }
}

/// The only connect affordance on Overview: an invite to unify the user's health data.
/// The per-source Connections list lives in Health → Connections.
struct UnifyHealthCard: View {
    var onConnect: (() -> Void)?

    var body: some View {
        TappableCard(onPress: onConnect, accessibilityLabel: "Unify your health information") {
            HStack(spacing: Theme.Spacing.lg) {
                sourceGlyphs

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Txt("Unify your health information", variant: .bodyEmphasized)
                    Txt("Connect labs, Whoop, and your scale into one private record on this phone.",
                        variant: .footnote, color: .labelSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Colors.labelTertiary)
            }
        }
    }

    private var sourceGlyphs: some View {
        HStack(spacing: -Theme.Spacing.sm) {
            sourceDisc { BrandLogo(.appleHealth, size: 28) }
            sourceDisc { BrandLogo(.whoop, size: 28) }
        }
    }

    private func sourceDisc<Logo: View>(@ViewBuilder _ logo: () -> Logo) -> some View {
        logo()
            .padding(Theme.Spacing.sm)
            .background(Circle().fill(Theme.Colors.surface))
            .overlay(Circle().stroke(Theme.Colors.surface, lineWidth: 2))
            .frame(width: 44, height: 44)
    }
}

/// Scrubbable 7-day recovery trend with the user's own typical band shaded behind the line and an
/// "Avg N%" pill. Tapping opens a MetricDetailSheet. Multi-day, so it doesn't re-scope with the day
/// picker. Display-only: the user's own readings vs their own typical, no interpretation or verdict.
struct RecoveryTrendCard: View {
    let points: [Double]
    var labels: [String] = []
    var latestLabel: String?
    /// The user's trailing average recovery %, shown as the "Avg N%" pill.
    var average: Int?
    /// The user's typical band (the shaded area on the chart).
    var typicalLow: Double?
    var typicalHigh: Double?

    @State private var showDetail = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rangeLabel: String? {
        guard let lo = typicalLow, let hi = typicalHigh else { return nil }
        return "\(Format.int(lo)) – \(Format.int(hi))"
    }

    var body: some View {
        Button {
            if reduceMotion { showDetail = true }
            else { withAnimation(Theme.Motion.stepTransition) { showDetail = true } }
        } label: {
            Card(metricAccent: Theme.Chart.recovery) {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    HStack(spacing: Theme.Spacing.sm) {
                        CardHeader(title: "RECOVERY TREND", icon: "chart.line.uptrend.xyaxis")
                        if let average {
                            avgPill(average)
                        }
                        Image(systemName: "chevron.forward")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.Colors.labelTertiary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                        if let latestLabel {
                            Text(latestLabel)
                                .font(Theme.Font.statNumber)
                                .foregroundStyle(Theme.Colors.label)
                            Txt("latest", variant: .footnote, color: .labelTertiary)
                        }
                        Spacer(minLength: 0)
                        Txt("last 7 days", variant: .footnote, color: .labelTertiary)
                    }
                    GeometryReader { geo in
                        InteractiveLineChart(
                            values: points, labels: labels,
                            rangeLow: typicalLow, rangeHigh: typicalHigh,
                            color: Theme.Chart.recovery,
                            width: geo.size.width, height: 130,
                            format: { "\(Int($0.rounded()))%" }
                        )
                    }
                    .frame(height: 130)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open recovery detail")
        .sheet(isPresented: $showDetail) {
            MetricDetailSheet(
                title: "Recovery",
                value: latestLabel.map { $0.replacingOccurrences(of: "%", with: "") } ?? "–",
                unit: "%",
                date: "last 7 days",
                rangeLabel: rangeLabel,
                series: points,
                labels: labels,
                rangeLow: typicalLow,
                rangeHigh: typicalHigh,
                color: Theme.Chart.recovery,
                statStripItems: detailStats,
                onClose: { showDetail = false }
            )
            .presentationDetents([.large])
            .presentationCornerRadius(28)
        }
    }

    private func avgPill(_ avg: Int) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text("Avg")
                .font(Theme.Font.footnote.weight(.medium))
                .foregroundStyle(Theme.Chart.recovery)
            Text("\(avg)%")
                .font(Theme.Font.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.Chart.recovery)
        }
        .padding(.vertical, Theme.Spacing.xs)
        .padding(.horizontal, Theme.Spacing.sm)
        .background(Capsule().fill(Theme.Chart.recovery.opacity(0.12)))
    }

    private var detailStats: [MetricStatStrip.Item] {
        guard !points.isEmpty else { return [] }
        let avg = average.map { "\($0)" } ?? Format.int(points.reduce(0, +) / Double(points.count))
        return [
            .init(label: "Avg", value: avg, unit: "%"),
            .init(label: "Min", value: Format.int(points.min() ?? 0), unit: "%"),
            .init(label: "Max", value: Format.int(points.max() ?? 0), unit: "%"),
            .init(label: "Latest", value: Format.int(points.last ?? 0), unit: "%"),
        ]
    }
}

#if DEBUG
#Preview("Overview · populated") {
    OverviewScreen()
        .environment(AppModel.sample)
}
#endif
