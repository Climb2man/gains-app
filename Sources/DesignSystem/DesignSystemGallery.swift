import SwiftUI

#if DEBUG

struct DesignSystemGallery: View {
    @State private var showDetail = false
    @State private var showPopup = false
    @State private var galleryField = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                Text("DesignSystem").font(Theme.Font.largeTitle)

                moreChartsSection
                caloriesSection
                activityIconsSection
                iconShowcase
                interactiveSection
                scoreCardSection
                ringsSection
                heroBackdropSection
                metricCardsSection
                sleepSection
                statRingsSection
                deviationSection
                goalSection
                sparklineSection
                healthRecordsSection
                badgesSection
                insightSection
                statStripSection
                floatingStatSection
                settingsRowsSection
                connectionRowsSection
                infoDisclosureSection
                onboardingSection
                skeletonSection
                heatmapSection
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .sheet(isPresented: $showDetail) {
            MetricDetailSheet(
                title: "Strain", value: "65", unit: "%", date: "Feb 19, 2025",
                rangeLabel: "vs your typical",
                series: [40, 32, 45, 38, 52, 60, 55, 48, 58, 66, 72, 64, 67],
                labels: ["7", "8", "9", "10", "11", "12", "13", "14", "15", "16", "17", "18", "19"],
                rangeLow: 34, rangeHigh: 67, color: Theme.Chart.strain,
                pills: ["Strain", "Exercise", "Daytime HR"],
                statStripItems: [
                    .init(label: "Avg", value: "55", unit: "%"),
                    .init(label: "Min", value: "32", unit: "%"),
                    .init(label: "Max", value: "72", unit: "%"),
                    .init(label: "Latest", value: "67", unit: "%"),
                ],
                goalLine: 60,
                onClose: { showDetail = false }
            )
            .presentationDetents([.large])
            .presentationCornerRadius(28)
        }
        .popup(isPresented: $showPopup) {
            GlassCard {
                VStack(spacing: 4) {
                    Text("8h 30m").font(Theme.Font.heroNumber).foregroundStyle(.white)
                    Text("Sleep Needed").font(Theme.Font.subhead).foregroundStyle(.white.opacity(0.85))
                }
            }
            .frame(width: 220)
        }
    }

    private var caloriesSection: some View {
        Section_("Calories: macro donut · progress · food qualities") {
            VStack(spacing: Theme.Spacing.lg) {
                MacroDonut(
                    segments: [
                        (value: 528, color: Theme.Chart.protein, label: "Protein"),
                        (value: 720, color: Theme.Chart.carbs, label: "Carbs"),
                        (value: 549, color: Theme.Chart.fat, label: "Fat"),
                    ],
                    size: 132, strokeWidth: 16,
                    centerLabel: "1,840", centerSubLabel: "kcal"
                )
                SurfaceCard {
                    MacroProgressCard(
                        macros: [
                            .init(label: "Protein", grams: 132, goal: 160, gradient: Theme.Chart.proteinGradient),
                            .init(label: "Carbs", grams: 180, goal: 206, gradient: Theme.Chart.carbsGradient),
                            .init(label: "Fat", grams: 84, goal: 73, gradient: Theme.Chart.fatGradient),
                        ],
                        micros: [.init(label: "Sugar", value: "44 g"), .init(label: "Fiber", value: "22 g")]
                    )
                }
                FoodQualityCard(items: [
                    (label: "Protein density", score: 0.82,
                     descriptor: "High protein for the calories vs your typical day."),
                    (label: "Fiber", score: 0.4,
                     descriptor: "A little below your usual fiber for this many calories."),
                    (label: "Added sugar", score: 0.25,
                     descriptor: "Lower added sugar than most of your logged days."),
                ])
            }
        }
    }

    private var interactiveSection: some View {
        Section_("Interactive: drag to scrub · tap to open detail") {
            VStack(spacing: Theme.Spacing.md) {
                InteractiveLineChart(
                    values: [62, 58, 71, 65, 80, 74, 69, 77, 85, 79, 88],
                    labels: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11"],
                    rangeLow: 60, rangeHigh: 85, color: Theme.Chart.strain, width: 300, height: 200)
                    .padding(Theme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.Colors.surface))

                HStack(spacing: Theme.Spacing.md) {
                    Button { showDetail = true } label: {
                        MetricCard(icon: "bolt.heart.fill", title: "Strain", value: "65", unit: "%",
                                        trend: .up, trendColor: Theme.Colors.tint, status: "Tap to open")
                    }.buttonStyle(.plain)
                    Button { showPopup = true } label: {
                        MetricCard(icon: "bed.double.fill", title: "Sleep", value: "8h", unit: "30m",
                                        status: "Tap for popup", accent: Theme.Chart.sleep)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var iconShowcase: some View {
        let icons = [
            "heart.fill", "waveform.path.ecg", "bed.double.fill", "figure.run",
            "figure.strengthtraining.traditional", "drop.fill", "flame.fill", "moon.stars.fill",
            "sun.max.fill", "lungs.fill", "brain.head.profile", "thermometer.medium",
            "testtube.2", "pills.fill", "fork.knife", "scalemass.fill",
            "shoeprints.fill", "bolt.heart.fill", "chart.line.uptrend.xyaxis", "calendar",
            "stopwatch.fill", "figure.cooldown", "figure.mind.and.body", "figure.pool.swim",
        ]
        return Section_("Icons") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: Theme.Spacing.md) {
                ForEach(icons, id: \.self) { name in
                    Image(systemName: name)
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.Colors.tint)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
            }
            .padding(Theme.Spacing.md)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.Colors.surface))
        }
    }

    private var scoreCardSection: some View {
        Section_("Score card + BenchmarkRangeChart") {
            ScoreCard(
                title: "Strain Score", value: "65%", date: "Feb 19, 2025", rangeLabel: "34 - 67%",
                metrics: ["Strain score", "Exercise Duration", "Daytime HR"],
                series: [40, 32, 45, 38, 52, 60, 55, 48, 58, 66, 72, 64, 67],
                rangeLow: 34, rangeHigh: 67, average: 66, averageLabel: "Avg. 66%",
                yTicks: [33, 67, 100], color: Theme.Chart.calories)
        }
    }

    private var ringsSection: some View {
        Section_("Gradient rings") {
            HStack(spacing: Theme.Spacing.lg) {
                GradientRing(progress: 0.70, title: "70%", caption: "recovered")
                GradientRing(progress: 0.42, title: "42%", caption: "strain",
                             gradient: [Theme.Chart.calories, Color(hex: "FFCC00")])
            }.frame(maxWidth: .infinity)
        }
    }

    private var heroBackdropSection: some View {
        Section_("Hero ring + backdrop (Overview)") {
            HeroBackdrop(recoveryPct: 94) {
                VStack(spacing: Theme.Spacing.lg) {
                    RingChart.hero(recoveryPct: 94)
                    HStack(spacing: Theme.Spacing.md) {
                        FloatingStatCard(icon: "waveform.path.ecg", title: "HRV", value: "128", unit: "ms",
                                         trend: .up, trendColor: Theme.Colors.onTint,
                                         accent: Theme.Colors.onTint, glass: true)
                        FloatingStatCard(icon: "heart.fill", title: "Resting HR", value: "49", unit: "bpm",
                                         trend: .down, trendColor: Theme.Colors.onTint,
                                         accent: Theme.Colors.onTint, glass: true)
                    }
                }
                .padding(Theme.Spacing.lg)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var metricCardsSection: some View {
        Section_("Metric cards (trend arrows)") {
            HStack(spacing: Theme.Spacing.md) {
                MetricCard(icon: "waveform.path.ecg", title: "Resting HRV", value: "85", unit: "ms",
                                trend: .up, trendColor: Theme.Colors.tint, status: "Above usual",
                                statusColor: Theme.Chart.activity)
                MetricCard(icon: "heart.fill", title: "Resting HR", value: "59", unit: "bpm",
                                trend: .down, trendColor: Theme.Chart.calories, status: "Steady")
            }
        }
    }

    private var sleepSection: some View {
        Section_("Sleep hypnogram + glass popup") {
            ZStack(alignment: .topTrailing) {
                SleepStagesChart(stages: [0, 1, 2, 2, 3, 3, 2, 1, 2, 3, 3, 2, 1, 2, 0, 1, 2, 3],
                                 width: 300, height: 150)
                    .padding(Theme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Color(hex: "1D2235")))
                GlassCard {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("8h 30m").font(Theme.Font.metricNumber).foregroundStyle(.white)
                        Text("Sleep Needed").font(Theme.Font.subhead).foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(Theme.Spacing.md)
            }
        }
    }

    private var statRingsSection: some View {
        Section_("Stat-ring tiles") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
                StatRingCard(label: "Awake", value: "1h 7m", percent: "10%", progress: 0.10, color: Theme.Chart.calories)
                StatRingCard(label: "REM", value: "1h 39m", percent: "21%", progress: 0.21, color: Theme.Chart.strain)
                StatRingCard(label: "Core", value: "4h 28m", percent: "57%", progress: 0.57, color: Theme.Chart.recovery)
                StatRingCard(label: "Deep", value: "56m", percent: "15%", progress: 0.15, color: Theme.Chart.sleep)
            }
        }
    }

    private var deviationSection: some View {
        Section_("Baseline-deviation chart") {
            BaselineDeviationChart(values: [0.2, -0.4, 0.6, 0.1, -0.2, 0.8, -0.5, 0.3, 0.5, -0.1, 0.4],
                                   width: 300, height: 130)
                .padding(Theme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.Colors.surface))
        }
    }

    private var goalSection: some View {
        Section_("Goal-bar chart") {
            GoalBarChart(values: [1800, 2100, 1950, 2300, 2000, 1700, 2250], goal: 2000,
                         width: 300, height: 130)
                .padding(Theme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.Colors.surface))
        }
    }

    private var sparklineSection: some View {
        Section_("Sparkline metric card") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill").font(.system(size: 13)).foregroundStyle(Theme.Colors.labelSecondary)
                        Text("Daytime HR").font(Theme.Font.subhead.weight(.medium)).foregroundStyle(Theme.Colors.labelSecondary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("45").font(Theme.Font.metricNumber).foregroundStyle(Theme.Colors.label)
                        Text("bpm").font(Theme.Font.callout).foregroundStyle(Theme.Colors.labelSecondary)
                    }
                    Label("vs your typical", systemImage: "arrow.down.circle.fill")
                        .font(Theme.Font.footnote.weight(.medium)).foregroundStyle(Theme.Colors.labelSecondary)
                }
                Spacer()
                Sparkline(values: [44, 46, 48, 47, 49, 50, 48, 46, 45], color: Theme.Chart.calories)
            }
            .padding(Theme.Spacing.lg)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.Colors.surface))
            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
        }
    }

    private var healthRecordsSection: some View {
        Section_("Health Records rows") {
            VStack(spacing: 0) {
                HealthRecordRow(category: "Medications", categoryColor: Theme.Colors.tint,
                                title: "Outpatient Clinical Visit", date: "Dec 11, 2025")
                Divider()
                HealthRecordRow(category: "Clinical Report", categoryColor: Theme.Chart.sleep,
                                title: "Comprehensive Psychological", date: "Dec 8, 2025")
                Divider()
                HealthRecordRow(category: "Lab Report", categoryColor: Theme.Colors.labelSecondary,
                                title: "Fasting Glucose and Metabolic", date: "Nov 20, 2025", biomarkers: 12)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.Colors.surface))
        }
    }

    private var badgesSection: some View {
        Section_("Badges") {
            HStack {
                CategoryBadge(text: "Medications", color: Theme.Colors.tint)
                CategoryBadge(text: "Clinical Report", color: Theme.Chart.sleep)
                BiomarkerBadge(count: 12)
            }
        }
    }

    private func chartCard<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        content()
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.Colors.surface))
    }

    private var moreChartsSection: some View {
        Group {
            Section_("Stacked bar") {
                chartCard { StackedBarChart(bars: [[3, 2, 1], [2, 3, 2], [1, 4, 2], [3, 1, 3], [2, 2, 4]], width: 300, height: 130) }
            }
            Section_("Positive / negative area") {
                chartCard { PositiveNegativeLineChart(values: [2, -1, 3, -2, 1, 4, -1, 2, -3, 1], width: 300, height: 130) }
            }
            Section_("Dynamic range: soft cloud band") {
                chartCard {
                    DynamicRangeChart(values: [62, 58, 71, 65, 80, 74, 69, 77, 85, 79],
                                      lower: [52, 50, 58, 55, 62, 60, 57, 63, 66, 64],
                                      upper: [74, 70, 82, 78, 90, 86, 82, 88, 95, 92],
                                      color: Theme.Chart.recovery, width: 300, height: 160)
                }
            }
            Section_("Radar") {
                chartCard {
                    HStack {
                        RadarChart(values: [0.8, 0.6, 0.9, 0.5, 0.7, 0.65], color: Theme.Chart.strain, size: 160)
                        Spacer()
                    }
                }
            }
            Section_("Projection (dashed future)") {
                chartCard { ProjectionChart(history: [60, 62, 61, 65, 68, 67], projection: [67, 70, 72, 75], width: 300, height: 130) }
            }
            Section_("Dual-ring gauge + pie") {
                chartCard {
                    HStack(spacing: Theme.Spacing.xl) {
                        DualRingGauge(outer: 0.7, inner: 0.45, title: "32", caption: "bio age", size: 130)
                        PieChart(values: [40, 25, 20, 15], size: 120)
                        Spacer()
                    }
                }
            }
            Section_("Sleep dial") {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Color(hex: "1D2235"))
                    SleepDialChart(size: 150).padding(Theme.Spacing.lg)
                }
                .frame(maxWidth: .infinity)
            }
            Section_("Legend") {
                ChartLegend(items: [("Awake", Theme.Chart.calories), ("REM", Theme.Chart.strain),
                                    ("Core", Theme.Chart.recovery), ("Deep", Theme.Chart.sleep)])
            }
        }
    }

    private var activityIconsSection: some View {
        let acts = ["running", "cycling", "swimming", "strength-training", "hiit", "mind-body",
                    "boxing", "rowing", "hiking", "basketball", "tennis", "golf",
                    "climbing", "dancing", "pilates", "jump-rope", "soccer", "skating-sports"]
        return Section_("Activity icons (SF Symbols, free)") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: Theme.Spacing.md) {
                ForEach(acts, id: \.self) { a in
                    Image(systemName: ActivityIcon.symbol(for: a))
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.Chart.activity)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
            }
            .padding(Theme.Spacing.md)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.Colors.surface))
        }
    }

    private var insightSection: some View {
        Section_("Insight card") {
            InsightCard(icon: "leaf.fill", title: "You're well recovered",
                             message: "Your recovery is strong today. Your resting HRV is 72.4 ms, "
                                + "above your usual 56.8 ms, and your resting heart rate is steady.")
        }
    }

    private var statStripSection: some View {
        Section_("Metric stat strip (avg / min / max / latest)") {
            MetricStatStrip(items: [
                .init(label: "Avg", value: "62", unit: "%"),
                .init(label: "Min", value: "48", unit: "%"),
                .init(label: "Max", value: "88", unit: "%"),
                .init(label: "Latest", value: "79", unit: "%"),
            ])
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.Colors.surface))
        }
    }

    private var floatingStatSection: some View {
        Section_("Floating stat cards (opaque + glass on hero)") {
            VStack(spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.md) {
                    FloatingStatCard(icon: "waveform.path.ecg", title: "HRV", value: "92", unit: "ms",
                                     trend: .up, trendColor: Theme.Colors.success, accent: Theme.Chart.protein)
                    FloatingStatCard(icon: "heart.fill", title: "Resting HR", value: "49", unit: "bpm",
                                     trend: .down, trendColor: Theme.Colors.success, accent: Theme.Chart.heartrate)
                }
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.card)
                        .fill(Theme.Chart.heroGradient(forRecovery: 78))
                    HStack(spacing: Theme.Spacing.md) {
                        FloatingStatCard(icon: "bolt.heart.fill", title: "Recovery", value: "78", unit: "%",
                                         trend: .up, trendColor: Theme.Colors.onTint,
                                         accent: Theme.Colors.onTint, glass: true)
                        FloatingStatCard(icon: "moon.fill", title: "Sleep", value: "8.4", unit: "h",
                                         trendColor: Theme.Colors.onTint, accent: Theme.Colors.onTint, glass: true)
                    }
                    .padding(Theme.Spacing.md)
                }
            }
        }
    }

    private var settingsRowsSection: some View {
        Section_("Settings rows + field + estimate strip") {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                SettingsGroup {
                    SettingsNavRow(icon: "person.crop.circle", accent: Theme.Colors.tint,
                                        title: "Profile", subtitle: "Male · 20 · 5'10\" · 206 lb") {}
                    SettingsValueRow(icon: "waveform.path.ecg", accent: Theme.Chart.recovery,
                                          title: "Whoop", value: "Linked")
                    SettingsValueRow(icon: "ruler", accent: Theme.Colors.labelSecondary,
                                          title: "Measurement system", value: "Imperial", disabled: true)
                }
                SettingsGroup {
                    SettingsNavRow(icon: "trash", accent: Theme.Colors.danger,
                                        title: "Delete my data", destructive: true) {}
                }
                FormField(label: "OpenRouter API key", text: $galleryField,
                           placeholder: "Paste your key", isSecure: true)
                EstimateStrip(
                    label: "Resting energy", value: "1,742", unit: "cal/day",
                    infoBody: "An estimate from your profile, not a medical measurement.")
            }
        }
    }

    private var connectionRowsSection: some View {
        Section_("Connection status rows") {
            VStack(spacing: Theme.Spacing.sm) {
                ConnectionStatusRow(title: "Whoop", systemImage: "bolt.heart",
                                    state: .connect(label: "Connect") {})
                ConnectionStatusRow(title: "Whoop", systemImage: "bolt.heart", state: .linked)
                ConnectionStatusRow(title: "Body weight", systemImage: "scalemass", state: .saved)
                ConnectionStatusRow(title: "Apple Health", systemImage: "heart.text.square", state: .requested)
                ConnectionStatusRow(title: "Apple Watch", systemImage: "applewatch",
                                    state: .unavailable("Not paired"))
            }
            .padding(Theme.Spacing.md)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.Colors.surface))
        }
    }

    private var infoDisclosureSection: some View {
        Section_("Info disclosure (tap the info icon)") {
            HStack(spacing: Theme.Spacing.sm) {
                Text("Resting heart rate")
                    .font(Theme.Font.bodyEmphasized).foregroundStyle(Theme.Colors.label)
                InfoDisclosure(
                    title: "vs your typical",
                    body: "This compares today's reading to your own recent baseline, not to a "
                        + "population. It's context on how today sits against your usual.")
                Spacer()
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.Colors.surface))
        }
    }

    private var onboardingSection: some View {
        Section_("Onboarding: step progress · halo mark · macro split") {
            VStack(spacing: Theme.Spacing.lg) {
                VStack(spacing: Theme.Spacing.md) {
                    StepProgressBar(current: 1, total: 4)
                    StepProgressBar(current: 3, total: 4)
                }
                OnboardingHaloMark(size: 120)
                MacroSplitBar(proteinG: 160, fatG: 73, carbsG: 206)
                    .padding(Theme.Spacing.lg)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.Colors.surface))
            }
        }
    }

    private var skeletonSection: some View {
        Section_("Skeleton loading card (shimmer)") {
            SkeletonCard()
        }
    }

    private var heatmapSection: some View {
        Section_("Recovery heatmap (year at a glance)") {
            let days: [RecoveryHeatmap.Day] = (0..<84).map { i in
                let pct: Double? = (i % 13 == 0) ? nil : Double((i * 41) % 100)
                return .init(date: String(format: "2026-%02d-%02d", (i / 28) + 1, (i % 28) + 1), pct: pct)
            }
            RecoveryHeatmap(days: days)
                .padding(Theme.Spacing.md)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.Colors.surface))
        }
    }
}

private struct Section_<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.content = content
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title).font(Theme.Font.footnote.weight(.semibold))
                .foregroundStyle(Theme.Colors.labelTertiary).textCase(.uppercase)
            content()
        }
    }
}

#Preview { DesignSystemGallery() }
#endif
