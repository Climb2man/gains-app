import SwiftUI

struct FoodLogView: View {
    @Environment(AppModel.self) private var appModel
    @State private var model: FoodLogViewModel
    /// The photo / menu / package capture flow. (Barcode is the view model's own flow.)
    @State private var capture: FoodCaptureCoordinator
    @FocusState private var composerFocused: Bool
    /// The selected day's live Whoop snapshot (steps + whole-day burn) for the activity strip in a
    /// real build, fetched per day so the Calories tab shows the same steps as Overview, not the demo
    /// fixture. nil until fetched or when unlinked.
    @State private var liveWhoop: WhoopSummary?

    /// When set (the Calories tab), the overview header is shown and this routes its "Macro insights"
    /// affordance to the deeper sheet. When nil (the quick-add FAB sheet), the header is omitted.
    var onOpenInsights: (() -> Void)?
    /// Open the scrubbable Calories detail sheet (the header ring tap). Only wired on the Calories tab.
    var onOpenDetail: (() -> Void)?

    init(
        appModel: AppModel,
        onOpenInsights: (() -> Void)? = nil,
        onOpenDetail: (() -> Void)? = nil
    ) {
        _model = State(initialValue: FoodLogViewModel(
            foodLog: appModel.foodLog,
            savedFoods: appModel.savedFoods,
            settings: appModel.foodLogSettings,
            nutrition: appModel.nutritionStore
        ))
        _capture = State(initialValue: FoodCaptureCoordinator(
            vision: appModel.foodVision,
            imageStore: appModel.foodImageStore,
            foodLog: appModel.foodLog,
            settings: appModel.foodLogSettings
        ))
        self.onOpenInsights = onOpenInsights
        self.onOpenDetail = onOpenDetail
    }

    var body: some View {
        VStack(spacing: 0) {
            DateStrip(
                selectedDate: model.selectedDay,
                onSelectDate: { model.selectedDay = $0 },
                days: DateStrip.trailingYear
            )
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.xs)

            notesList
                .gesture(daySwipe)

            if onOpenInsights == nil {
                HairlineDivider()
                FoodCaptureBar(
                    coordinator: capture,
                    onScanBarcode: { composerFocused = false; model.beginScanBarcode() }
                )

                FoodComposer(
                    text: $model.composerText,
                    isFocused: $composerFocused,
                    shortcuts: model.filteredShortcuts,
                    recents: model.filteredRecents,
                    onSubmit: { model.submitComposer(); composerFocused = false },
                    onLogShortcut: { model.logShortcut($0) },
                    onLogRecent: { model.logRecent($0) },
                    onScanBarcode: { composerFocused = false; model.beginScanBarcode() }
                )
            }
        }
        .background(Theme.Colors.background)
        .onAppear { if onOpenInsights == nil { composerFocused = true } }
        .onChange(of: appModel.selectedDate) { _, date in
            // The shell resets `selectedDate` to today on foreground; this model captured its day in
            // `init`, so without this an overnight suspend leaves the log on yesterday.
            model.selectedDay = FoodLogStore.dayKey(date)
        }
        .task(id: model.selectedDay) {
            guard !appModel.usesSampleData, appModel.whoopLinked else { liveWhoop = nil; return }
            let day = model.selectedDay
            let isToday = day == DateStrip.toKey(Date())
            let summary = await appModel.whoop.summary(date: isToday ? nil : day, force: false)
            // `.task(id:)` cancels the previous task on a day change, but `WhoopClient.summary` de-dupes
            // through an unstructured Task that does not observe cancellation, so a slower fetch for an
            // EARLIER day still resumes here. Assigning it would show that day's steps and burn under
            // the current day's header. `OverviewModel.loadWhoopSummary` guards the same way.
            guard day == model.selectedDay else { return }
            liveWhoop = summary
        }
        .overlay { captureAnalyzingOverlay }
        .sheet(isPresented: estimateSheetPresented) {
            if case .reviewingEstimate(let review) = capture.phase {
                FoodEstimateReviewSheet(
                    review: review,
                    bias: model.bias,
                    onConfirm: { capture.confirmEstimate($0, from: review); model.goToToday() },
                    onCancel: { capture.dismiss() }
                )
            }
        }
        .sheet(isPresented: menuSheetPresented) {
            if case .reviewingMenu(let review) = capture.phase {
                MenuScanSheet(
                    candidates: review.candidates,
                    onConfirm: { capture.confirmMenuPicks($0); model.goToToday() },
                    onCancel: { capture.dismiss() }
                )
            }
        }
        .alert("Couldn't use that capture", isPresented: captureErrorPresented) {
            Button("OK") { capture.dismiss() }
        } message: {
            Txt(captureErrorMessage, variant: .footnote)
        }
        .sheet(item: $model.savingEntry) { entry in
            SaveFoodSheet(entry: entry, savedFoods: appModel.savedFoods)
        }
        .sheet(item: $model.editingEntry) { entry in
            EditFoodSheet(
                entry: entry,
                bias: model.bias,
                onRetype: { model.retype(entry, to: $0) },
                onCorrectItem: { model.correctItem(entry, item: $0) }
            )
        }
        .sheet(isPresented: $model.isScanningBarcode) {
            BarcodeScannerView(
                onLog: { item in model.logScannedItem(item) },
                onDismiss: { model.isScanningBarcode = false }
            )
        }
        #if DEBUG
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--present-add-food"), let entry = model.entries.first(where: canSave) {
                model.beginEdit(entry)
            }
            if args.contains("--focus-composer") {
                composerFocused = true
            }
        }
        #endif
    }

    @ViewBuilder
    private var notesList: some View {
        let entries = model.entries
        if entries.isEmpty {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    overviewHeader
                    EmptyDayState(isToday: model.isToday) { composerFocused = true }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, 96)
            }
            .scrollDismissesKeyboard(.interactively)
        } else {
            List {
                if onOpenInsights != nil {
                    Section {
                        overviewHeader
                            .listRowInsets(EdgeInsets(top: 0, leading: 0,
                                                      bottom: Theme.Spacing.xs, trailing: 0))
                            .listRowBackground(Theme.Colors.background)
                            .listRowSeparator(.hidden)
                    }
                }
                Section {
                    ForEach(entries) { entry in
                        FoodLogRow(
                            entry: entry,
                            expanded: model.expandedEntryID == entry.id,
                            onTapDetails: { model.toggleDetails(entry) }
                        )
                        .listRowInsets(EdgeInsets(top: Theme.Spacing.sm, leading: Theme.Spacing.lg,
                                                  bottom: Theme.Spacing.sm, trailing: Theme.Spacing.lg))
                        .listRowBackground(Theme.Colors.surface)
                        .listRowSeparatorTint(Theme.Colors.separator)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { model.delete(entry) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            if canSave(entry) {
                                Button { model.beginEdit(entry) } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(Theme.Colors.tint)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if canSave(entry) {
                                Button { model.beginSave(entry) } label: {
                                    Label("Save", systemImage: "bookmark.fill")
                                }
                                .tint(Theme.Colors.success)
                            }
                        }
                        .contextMenu { contextMenu(entry) }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .contentMargins(.top, Theme.Spacing.xs, for: .scrollContent)
            .contentMargins(.bottom, 96, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    /// The macro overview header (Calories tab only). Shows the day's totals vs goals; its insights and
    /// detail affordances route through the shell's callbacks.
    @ViewBuilder
    private var overviewHeader: some View {
        if onOpenInsights != nil {
            VStack(spacing: Theme.Spacing.md) {
                CalorieOverviewHeader(
                    totals: model.totals,
                    goals: model.goals,
                    onOpenDetail: { onOpenDetail?() }
                )
                // Today only. The Calories tab can scroll back through past days, and logging a
                // suggestion routes through logRecent, which calls goToToday() — so on a past day
                // the card would compute its gap from THAT day and then silently log the food
                // against today. Suggesting what to eat for a day that has already finished is
                // meaningless regardless.
                if model.isToday {
                    CloseYourRingsCard(
                        totals: model.totals,
                        goals: model.goals,
                        candidates: model.suggestionCandidates,
                        onLog: { model.logSuggestion($0) }
                    )
                }
                activityStrip
                weeklyTrendsCard
                foodQualityView
            }
        }
    }

    /// Three columns: steps, active calories (whole-day burn minus resting BMR), and water, from the
    /// user's own Whoop snapshot and logged water. Each value falls back to "–"; the strip hides when
    /// all three are absent.
    @ViewBuilder
    private var activityStrip: some View {
        let steps = daySummary?.steps?.count
        let burn = daySummary?.calories
        let water = model.totals.waterMilliliters
        if steps != nil || burn != nil || water > 0 {
            Card {
                HStack(spacing: 0) {
                    activityColumn(
                        icon: "figure.walk",
                        label: "Steps",
                        value: steps.map { Format.int(Double($0)) } ?? "–",
                        unit: nil
                    )
                    activityDivider
                    activityColumn(
                        icon: "flame.fill",
                        label: "Activity",
                        value: burn.map { Format.int(activeCalories(burn: $0)) } ?? "–",
                        unit: burn != nil ? "kcal" : nil
                    )
                    activityDivider
                    activityColumn(
                        icon: "drop.fill",
                        label: "Water",
                        value: water > 0 ? FoodLogFormat.water(water) : "–",
                        unit: nil
                    )
                }
            }
        }
    }

    /// Active calories = whole-day burn minus resting BMR, clamped at 0. Falls back to raw burn when
    /// there's no profile to estimate BMR. A labeled estimate, never advice.
    private func activeCalories(burn: Double) -> Double {
        guard let profile = appModel.profile else { return burn }
        return max(0, burn - EnergyMath.computeBmr(profile))
    }

    private var activityDivider: some View {
        Rectangle()
            .fill(Theme.Colors.separator)
            .frame(width: 1, height: 28)
    }

    @ViewBuilder
    private func activityColumn(icon: String, label: String, value: String, unit: String?) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.labelTertiary)
                Txt(label, variant: .footnote, color: .labelSecondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Txt(value, variant: .bodyEmphasized)
                if let unit {
                    Txt(unit, variant: .footnote, color: .labelTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// A 14-day calorie trend: the user's logged calories over two weeks, averaged over logged days.
    /// Descriptive only, no goal verdict or advice.
    private var weeklyTrendsCard: some View {
        let history = appModel.nutritionStore.dailyHistory(14)
        let series = history.map { $0.totals.calories }
        let logged = series.filter { $0 > 0 }
        let avg = logged.isEmpty ? 0 : logged.reduce(0, +) / Double(logged.count)
        return Card(metricAccent: Theme.Chart.calories) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack {
                    Text("LAST 14 DAYS")
                        .font(Theme.Font.footnote.weight(.semibold))
                        .tracking(0.5)
                        .foregroundStyle(Theme.Colors.labelTertiary)
                    Spacer()
                    Text("\(Format.int(avg)) kcal avg")
                        .font(Theme.Font.footnote)
                        .foregroundStyle(Theme.Colors.labelSecondary)
                }
                GeometryReader { geo in
                    Sparkline(
                        values: series,
                        color: Theme.Chart.calories,
                        width: geo.size.width,
                        height: 44
                    )
                }
                .frame(height: 44)
            }
        }
    }

    /// Descriptive food attributes (protein density, fiber, added sugar for the calories) of the day's
    /// totals. Hidden when nothing is logged. Scores the food, never the eater.
    @ViewBuilder
    private var foodQualityView: some View {
        let items = CaloriesSupport.foodQualities(model.totals)
        if !items.isEmpty {
            FoodQualityCard(items: items)
        }
    }

    @ViewBuilder
    private func contextMenu(_ entry: FoodJournalEntry) -> some View {
        if canSave(entry) {
            Button { model.beginSave(entry) } label: {
                Label("Save & nickname", systemImage: "bookmark")
            }
            Button { model.beginEdit(entry) } label: {
                Label("Is something wrong? Edit", systemImage: "pencil")
            }
        }
        if entry.status == .failed {
            Button { model.retry(entry) } label: {
                Label("Retry estimate", systemImage: "arrow.clockwise")
            }
        }
        Button(role: .destructive) { model.delete(entry) } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    /// Only resolved, non-water lines can be saved as a shortcut (a pending/failed line has no macros).
    private func canSave(_ entry: FoodJournalEntry) -> Bool {
        entry.status == .resolved && !entry.items.isEmpty
    }

    /// The selected day's Whoop snapshot for the activity strip. The demo container shows SampleData on
    /// the reference day; a real build shows the user's live snapshot (`liveWhoop`, fetched in `.task`)
    /// so Calories steps match Overview.
    private var daySummary: WhoopSummary? {
        guard appModel.whoopLinked else { return nil }
        if appModel.usesSampleData {
            return model.selectedDay == DateStrip.toKey(SampleData.referenceDate) ? SampleData.whoopSummary : nil
        }
        return liveWhoop
    }

    @ViewBuilder
    private var captureAnalyzingOverlay: some View {
        if case .analyzing(let kind) = capture.phase {
            CaptureAnalyzingOverlay(label: kind.analyzingLabel)
        }
    }

    /// Present the estimate-review sheet while the coordinator is in `.reviewingEstimate`.
    private var estimateSheetPresented: Binding<Bool> {
        Binding(
            get: { if case .reviewingEstimate = capture.phase { true } else { false } },
            set: { if !$0 { capture.dismiss() } }
        )
    }

    /// Present the menu-scan sheet while the coordinator is in `.reviewingMenu`.
    private var menuSheetPresented: Binding<Bool> {
        Binding(
            get: { if case .reviewingMenu = capture.phase { true } else { false } },
            set: { if !$0 { capture.dismiss() } }
        )
    }

    /// Show the capture error alert while the coordinator is in `.error`.
    private var captureErrorPresented: Binding<Bool> {
        Binding(
            get: { if case .error = capture.phase { true } else { false } },
            set: { if !$0 { capture.dismiss() } }
        )
    }

    private var captureErrorMessage: String {
        if case .error(let message) = capture.phase { message } else { "" }
    }

    private var daySwipe: some Gesture {
        DragGesture(minimumDistance: 40, coordinateSpace: .local)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width > 0 {
                    model.goToPreviousDay()
                } else {
                    model.goToNextDay()
                }
            }
    }
}

private struct EmptyDayState: View {
    let isToday: Bool
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            EmptyStateCard(
                icon: "fork.knife",
                title: isToday ? "Nothing logged yet" : "No food logged this day",
                message: isToday
                    ? "Type what you ate below in plain English: “chicken bowl”, “16 oz water”. We'll estimate the macros."
                    : "Swipe back to today to log a meal."
            )
            if isToday {
                Button(action: onAdd) {
                    Txt("Add a line", variant: .bodyEmphasized, color: .tint)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#if DEBUG
#Preview("Food log") {
    FoodLogView(appModel: .sample)
        .environment(AppModel.sample)
}
#endif
