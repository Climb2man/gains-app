import SwiftUI

struct DashboardHeader: View {
    /// Stored full name; greets the first word, or "there" when unset.
    var name: String?
    /// Called when the settings button is tapped.
    var onOpenSettings: (() -> Void)?
    /// Called when the journal button is tapped.
    var onOpenJournal: (() -> Void)?

    private static let defaultFirstName = "there"

    private var firstName: String {
        let first = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
        return first.isEmpty ? Self.defaultFirstName : first
    }

    private static let todayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter
    }()

    private var todayLabel: String {
        Self.todayFormatter.string(from: Date()).lowercased()
    }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Hi \(firstName) 👋")
                    .font(Theme.Font.title2)
                    .foregroundStyle(Theme.Colors.label)
                Text(todayLabel)
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Colors.labelSecondary)
            }
            Spacer(minLength: 0)
            journalButton
            settingsButton
        }
    }

    private var journalButton: some View {
        Button {
            onOpenJournal?()
        } label: {
            Image(systemName: "book.closed")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.Colors.labelSecondary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Theme.Colors.surface2))
        }
        .buttonStyle(.plain)
        .disabled(onOpenJournal == nil)
        .accessibilityLabel("Journal")
    }

    private var settingsButton: some View {
        Button {
            onOpenSettings?()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.Colors.labelSecondary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Theme.Colors.surface2))
        }
        .buttonStyle(.plain)
        .disabled(onOpenSettings == nil)
        .accessibilityLabel("Settings")
    }
}
