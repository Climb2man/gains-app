import SwiftUI

struct AddFoodView: View {
    @Environment(AppModel.self) private var appModel
    @State private var model: FoodLogViewModel
    /// The photo / menu / package capture flow. (Barcode is the view model's own flow.)
    @State private var capture: FoodCaptureCoordinator
    @FocusState private var composerFocused: Bool
    /// Presents the Recent history screen from the composer's clock button.
    @State private var showingRecents = false

    /// Built from `appModel`'s stores the same way as `FoodLogView.init`, so both surfaces share one
    /// engine and write to the same journal.
    init(appModel: AppModel) {
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
    }

    var body: some View {
        todayList
            .safeAreaInset(edge: .bottom, spacing: 0) {
                AddFoodComposerBar(
                    model: model, capture: capture, composerFocused: $composerFocused,
                    onOpenRecents: { showingRecents = true }
                )
            }
            .background(Theme.Colors.background)
            .sheet(isPresented: $showingRecents) {
                NavigationStack { RecentMealsScreen() }
            }
        .onAppear { composerFocused = true }
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
            if ProcessInfo.processInfo.arguments.contains("--focus-composer") {
                composerFocused = true
            }
            if ProcessInfo.processInfo.arguments.contains("--prefill-food") {
                model.composerText = "Te"
                composerFocused = true
            }
        }
        #endif
    }

    @ViewBuilder
    private var todayList: some View {
        let entries = model.entries
        if entries.isEmpty {
            ScrollView {
                AddFoodEmptyState()
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
        } else {
            List {
                Section {
                    ForEach(entries) { entry in
                        FoodLogRow(
                            entry: entry,
                            expanded: model.expandedEntryID == entry.id,
                            onTapDetails: { model.toggleDetails(entry) },
                            onEdit: canSave(entry) ? { model.beginEdit(entry) } : nil
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
                } header: {
                    Txt("Today", variant: .footnote, color: .labelSecondary)
                        .textCase(nil)
                }
            }
            .listStyle(.insetGrouped)
            .contentMargins(.top, Theme.Spacing.xs, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            .scrollDismissesKeyboard(.interactively)
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

    /// Only resolved lines with items can be saved as a shortcut (pending/failed lines have no macros).
    private func canSave(_ entry: FoodJournalEntry) -> Bool {
        entry.status == .resolved && !entry.items.isEmpty
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
}

/// Pinned capture-tiles + composer block. Extracted so the `model.composerText` reads (via
/// `filteredShortcuts` / `filteredRecents`) invalidate only this body. Inline in `AddFoodView.body`,
/// every keystroke re-derived `model.entries` (a full journal pass) and rebuilt the day's List.
private struct AddFoodComposerBar: View {
    @Bindable var model: FoodLogViewModel
    let capture: FoodCaptureCoordinator
    var composerFocused: FocusState<Bool>.Binding
    let onOpenRecents: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HairlineDivider()
            FoodCaptureBar(
                coordinator: capture,
                onScanBarcode: { composerFocused.wrappedValue = false; model.beginScanBarcode() }
            )
            FoodComposer(
                text: $model.composerText,
                isFocused: composerFocused,
                shortcuts: model.filteredShortcuts,
                recents: model.filteredRecents,
                onSubmit: { model.submitComposer(); composerFocused.wrappedValue = false },
                onLogShortcut: { model.logShortcut($0) },
                onLogRecent: { model.logRecent($0) },
                onScanBarcode: { composerFocused.wrappedValue = false; model.beginScanBarcode() },
                onOpenRecents: { composerFocused.wrappedValue = false; onOpenRecents() }
            )
        }
    }
}

/// Empty state before the first line: a card nudging the user to type in the composer above.
/// Description only, no advice or goal verdict.
private struct AddFoodEmptyState: View {
    var body: some View {
        EmptyStateCard(
            icon: "fork.knife",
            title: "Type what you ate above",
            message: "In plain English: “chicken bowl”, “16 oz water”. We'll estimate the macros. Every line stays editable."
        )
    }
}

#if DEBUG
#Preview("Add food") {
    NavigationStack {
        AddFoodView(appModel: .sample)
            .navigationTitle("Log food")
            .navigationBarTitleDisplayMode(.inline)
    }
    .environment(AppModel.sample)
}
#endif
