import SwiftUI

struct JournalScreen: View {
    private let store: JournalStore

    @State private var selectedDay: String
    @State private var composerText = ""
    @FocusState private var composerFocused: Bool

    /// The note being edited (drives the edit alert) + its draft text.
    @State private var editingNote: JournalNote?
    @State private var draftText = ""

    /// Opens on `day` (a local `YYYY-MM-DD` key, e.g. Overview's selected day) or today.
    init(store: JournalStore, day: String? = nil) {
        self.store = store
        _selectedDay = State(initialValue: day ?? JournalStore.dayKey(.now))
    }

    private var todayKey: String { JournalStore.dayKey(.now) }
    private var isToday: Bool { selectedDay == todayKey }

    var body: some View {
        VStack(spacing: 0) {
            FoodLogDayHeader(
                title: CaloriesSupport.dayTitle(selectedDay),
                isToday: isToday,
                onPrevious: { shiftDay(-1) },
                onNext: { shiftDay(1) },
                onToday: { selectedDay = todayKey }
            )
            HairlineDivider()

            notesList

            composer
        }
        .background(Theme.Colors.background)
        .gesture(daySwipe)
        .navigationTitle("Journal")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Edit note", isPresented: editingPresented) {
            TextField("Note", text: $draftText)
            Button("Cancel", role: .cancel) { editingNote = nil }
            Button("Save") {
                if let note = editingNote { store.editNote(id: note.id, newText: draftText) }
                editingNote = nil
            }
        }
    }

    @ViewBuilder
    private var notesList: some View {
        let notes = store.notes(on: selectedDay)
        if notes.isEmpty {
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    EmptyStateCard(
                        icon: "note.text",
                        title: isToday ? "No notes yet" : "No notes this day",
                        message: isToday
                            ? "Write anything: how the day went, how you felt, what you want to remember."
                            : "Notes land on the day you write them. Swipe back to today to add one."
                    )
                    if isToday {
                        Button { composerFocused = true } label: {
                            Txt("Write a note", variant: .bodyEmphasized, color: .tint)
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
                    ForEach(notes) { note in
                        JournalNoteRow(note: note)
                            .listRowInsets(EdgeInsets(top: 0, leading: Theme.Spacing.lg,
                                                      bottom: 0, trailing: Theme.Spacing.lg))
                            .listRowBackground(Theme.Colors.background)
                            .listRowSeparatorTint(Theme.Colors.separator)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) { store.removeNote(id: note.id) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button { beginEdit(note) } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(Theme.Colors.tint)
                            }
                            .contextMenu {
                                Button { beginEdit(note) } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button(role: .destructive) { store.removeNote(id: note.id) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                } footer: {
                    Txt("Your private notes. They stay on this device.",
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

    private var composer: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "note.text")
                .font(.system(size: 22))
                .foregroundStyle(Theme.Colors.tint)

            TextField("Write a note…", text: $composerText, axis: .vertical)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Colors.label)
                .lineLimit(1...5)
                .textInputAutocapitalization(.sentences)
                .focused($composerFocused)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .fill(Theme.Colors.fieldBackground)
                )
                .accessibilityLabel("Write a journal note")

            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSubmit ? Theme.Colors.tint : Theme.Colors.labelTertiary)
            }
            .disabled(!canSubmit)
            .accessibilityLabel("Save this note")
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.surface)
        .overlay(alignment: .top) { HairlineDivider() }
    }

    private var canSubmit: Bool {
        !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Notes always land on today (a real timestamp); jump there so the new note is visible.
    private func submit() {
        guard canSubmit else { return }
        selectedDay = todayKey
        store.addNote(composerText)
        composerText = ""
    }

    private func beginEdit(_ note: JournalNote) {
        draftText = note.text
        editingNote = note
    }

    private var editingPresented: Binding<Bool> {
        Binding(get: { editingNote != nil }, set: { if !$0 { editingNote = nil } })
    }

    private func shiftDay(_ delta: Int) {
        if delta > 0, isToday { return }
        let base = CaloriesSupport.keyToDate(selectedDay)
        guard let shifted = Calendar.current.date(byAdding: .day, value: delta, to: base) else { return }
        selectedDay = JournalStore.dayKey(shifted)
    }

    private var daySwipe: some Gesture {
        DragGesture(minimumDistance: 40, coordinateSpace: .local)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                shiftDay(value.translation.width > 0 ? -1 : 1)
            }
    }
}

/// One note: its local time-of-day above the text, verbatim.
private struct JournalNoteRow: View {
    let note: JournalNote

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Txt(timeLabel, variant: .footnote, color: .labelTertiary)
            Txt(note.text, variant: .body)
        }
        .padding(.vertical, Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    private var timeLabel: String {
        guard let date = JournalStore.parseISO(note.date) else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

#if DEBUG
#Preview("Journal") {
    NavigationStack { JournalScreen(store: AppModel.sample.journal) }
}
#endif
