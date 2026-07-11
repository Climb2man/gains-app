import SwiftUI

@MainActor
struct RecentMealsScreen: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    /// Transient "Logged ✓" confirmation after a re-log.
    @State private var loggedNote: String?

    /// Recent resolved lines grouped by local day, preserving the newest-first order recentLines() gives.
    private var grouped: [(day: String, lines: [FoodJournalEntry])] {
        var order: [String] = []
        var byDay: [String: [FoodJournalEntry]] = [:]
        for entry in appModel.foodLog.recentLines() {
            let key = FoodLogStore.localDayKey(forISO: entry.loggedAt)
            if byDay[key] == nil { order.append(key) }
            byDay[key, default: []].append(entry)
        }
        return order.map { ($0, byDay[$0] ?? []) }
    }

    var body: some View {
        Group {
            if grouped.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(Theme.Colors.background)
        .navigationTitle("Recent")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done", action: dismiss.callAsFunction)
            }
        }
        .overlay(alignment: .bottom) {
            if let note = loggedNote {
                Txt(note, variant: .footnote, color: .onTint)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Capsule().fill(Theme.Colors.tint))
                    .padding(.bottom, Theme.Spacing.xl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var list: some View {
        List {
            ForEach(grouped, id: \.day) { section in
                Section {
                    ForEach(section.lines) { line in
                        Button { relog(line) } label: { row(line) }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: Theme.Spacing.sm, leading: Theme.Spacing.lg,
                                                      bottom: Theme.Spacing.sm, trailing: Theme.Spacing.lg))
                            .listRowBackground(Theme.Colors.surface)
                    }
                } header: {
                    Txt(CaloriesSupport.dayTitle(section.day), variant: .footnote, color: .labelSecondary)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
    }

    private func row(_ line: FoodJournalEntry) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Txt(line.displayTitle, variant: .bodyEmphasized).lineLimit(1)
                Txt(subtitle(line), variant: .footnote, color: .labelSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Theme.Colors.tint)
        }
        .contentShape(.rect)
    }

    private func subtitle(_ line: FoodJournalEntry) -> String {
        let p = line.items.reduce(0) { $0 + $1.proteinG }
        let c = line.items.reduce(0) { $0 + $1.carbsG }
        let f = line.items.reduce(0) { $0 + $1.fatG }
        return "\(Format.int(line.totalCalories)) kcal · " + FoodLogFormat.macroLine(protein: p, carbs: c, fat: f)
    }

    private var emptyState: some View {
        ScrollView {
            EmptyStateCard(
                icon: "clock.arrow.circlepath",
                title: "No recent meals yet",
                message: "Everything you log appears here automatically, newest first. Tap any one to log it again. (For meals you bookmark and name, use Saved meals in the ••• menu.)"
            )
            .padding(Theme.Spacing.lg)
        }
    }

    /// Re-log a recent line onto today. No AI: it's an already-resolved snapshot, and `logShortcut`
    /// copies the items with fresh ids so the new line is independent of the original.
    private func relog(_ line: FoodJournalEntry) {
        appModel.foodLog.logShortcut(FoodShortcut(
            nickname: line.displayTitle,
            items: line.items,
            source: "recent",
            createdAt: FoodLogStore.isoNow(),
            updatedAt: FoodLogStore.isoNow()
        ))
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        withAnimation { loggedNote = "Logged \(line.displayTitle) to today" }
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation { loggedNote = nil }
        }
    }
}

#if DEBUG
#Preview("Recent meals") {
    NavigationStack { RecentMealsScreen() }
        .environment(AppModel.sample)
}
#endif
