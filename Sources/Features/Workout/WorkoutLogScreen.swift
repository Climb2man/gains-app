import SwiftUI

struct WorkoutLogScreen: View {
    @State private var model: WorkoutLogViewModel
    @FocusState private var composerFocused: Bool

    /// A draft string for the save/edit text-field alerts.
    @State private var draftText = ""

    init(store: WorkoutStore) {
        _model = State(initialValue: WorkoutLogViewModel(store: store))
    }

    var body: some View {
        VStack(spacing: 0) {
            FoodLogDayHeader(
                title: model.dayTitle,
                isToday: model.isToday,
                onPrevious: model.goToPreviousDay,
                onNext: model.goToNextDay,
                onToday: model.goToToday
            )
            HairlineDivider()

            sessionsList

            WorkoutComposer(
                text: $model.composerText,
                isFocused: $composerFocused,
                shortcuts: model.shortcuts,
                onSubmit: { model.submitComposer(); composerFocused = false },
                onLogShortcut: { model.logShortcut($0) }
            )
        }
        .background(Theme.Colors.background)
        .gesture(daySwipe)
        .alert("Save workout", isPresented: savingPresented) {
            TextField("Nickname (e.g. Push day)", text: $draftText)
            Button("Cancel", role: .cancel) { model.savingEntry = nil }
            Button("Save") {
                if let entry = model.savingEntry { model.saveShortcut(entry, nickname: draftText) }
                model.savingEntry = nil
            }
        } message: {
            Txt("Re-log this workout in one tap from the quick-add row.", variant: .footnote)
        }
        .alert("Edit workout", isPresented: editingPresented) {
            TextField("Workout text", text: $draftText)
            Button("Cancel", role: .cancel) { model.editingEntry = nil }
            Button("Re-parse") {
                if let entry = model.editingEntry { model.retype(entry, to: draftText) }
                model.editingEntry = nil
            }
        } message: {
            Txt("Re-type the workout in any notation; we'll re-read it.", variant: .footnote)
        }
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("--focus-workout-composer") {
                composerFocused = true
            }
        }
        #endif
    }

    @ViewBuilder
    private var sessionsList: some View {
        let entries = model.entries
        if entries.isEmpty {
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    EmptyStateCard(
                        icon: "dumbbell.fill",
                        title: model.isToday ? "No workout logged yet" : "No workout this day",
                        message: model.isToday
                            ? "Type your session below in any notation: “Bench 3x10 @135, incline DB 10,10,8 @50”. We'll normalize it."
                            : "Swipe back to today to log a session."
                    )
                    if model.isToday {
                        Button { composerFocused = true } label: {
                            Txt("Log a workout", variant: .bodyEmphasized, color: .tint)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
        } else {
            List {
                Section {
                    ForEach(entries) { entry in
                        WorkoutLogRow(
                            entry: entry,
                            expanded: model.expandedEntryID == entry.id,
                            onTapDetails: { model.toggleDetails(entry) }
                        )
                        .listRowInsets(EdgeInsets(top: 0, leading: Theme.Spacing.lg,
                                                  bottom: 0, trailing: Theme.Spacing.lg))
                        .listRowBackground(Theme.Colors.background)
                        .listRowSeparatorTint(Theme.Colors.separator)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { model.delete(entry) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            if canSave(entry) {
                                Button { beginEdit(entry) } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(Theme.Colors.tint)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if canSave(entry) {
                                Button { beginSave(entry) } label: {
                                    Label("Save", systemImage: "bookmark.fill")
                                }
                                .tint(Theme.Colors.success)
                            }
                        }
                        .contextMenu { contextMenu(entry) }
                    }
                } footer: {
                    Txt("Your logged training, normalized. Not coaching or medical advice.",
                        variant: .footnote, color: .labelTertiary)
                        .padding(.top, Theme.Spacing.sm)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    @ViewBuilder
    private func contextMenu(_ entry: WorkoutEntry) -> some View {
        if canSave(entry) {
            Button { beginSave(entry) } label: {
                Label("Save & nickname", systemImage: "bookmark")
            }
            Button { beginEdit(entry) } label: {
                Label("Edit", systemImage: "pencil")
            }
        }
        if entry.status == .failed {
            Button { model.retry(entry) } label: {
                Label("Retry parse", systemImage: "arrow.clockwise")
            }
        }
        Button(role: .destructive) { model.delete(entry) } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    /// Only resolved sessions with exercises can be saved/edited (a pending/failed one has no snapshot).
    private func canSave(_ entry: WorkoutEntry) -> Bool {
        entry.status == .resolved && !entry.exercises.isEmpty
    }

    private func beginSave(_ entry: WorkoutEntry) {
        draftText = entry.displayTitle
        model.beginSave(entry)
    }

    private func beginEdit(_ entry: WorkoutEntry) {
        draftText = entry.rawText
        model.beginEdit(entry)
    }

    private var savingPresented: Binding<Bool> {
        Binding(get: { model.savingEntry != nil }, set: { if !$0 { model.savingEntry = nil } })
    }

    private var editingPresented: Binding<Bool> {
        Binding(get: { model.editingEntry != nil }, set: { if !$0 { model.editingEntry = nil } })
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

#if DEBUG
#Preview("Workout log") {
    WorkoutLogScreen(store: AppModel.sample.workoutLog)
}
#endif
