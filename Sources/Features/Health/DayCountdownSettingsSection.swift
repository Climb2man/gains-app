import SwiftUI
import WidgetKit

/// Sets the Day Countdown lock-screen widget's target: a calendar `DatePicker` plus an optional label,
/// written to the App Group the widget reads. Saving reloads the widget so the count updates right away.
@MainActor
struct DayCountdownSettingsSection: View {
    @State private var date = CountdownConfig.endOfYear()
    @State private var label = ""
    @State private var saved = false

    private var daysLeft: Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: Date()),
                                  to: cal.startOfDay(for: date)).day ?? 0
    }

    private var daysPhrase: String {
        switch daysLeft {
        case 0: return "That's today"
        case 1: return "1 day left"
        case let d where d > 1: return "\(d) days left"
        case -1: return "1 day ago"
        default: return "\(abs(daysLeft)) days ago"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionCaption(title: "Day Countdown")
            SurfaceCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Txt("Pick a date to count down to on your Lock Screen widget.",
                        variant: .footnote, color: .labelSecondary)

                    DatePicker("Target date", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(Theme.Colors.tint)
                        .onChange(of: date) { saved = false }

                    FormField(label: "Label (optional)", text: $label,
                               placeholder: "e.g. Trip, Cut ends", autocap: .words)
                        .onChange(of: label) { saved = false }

                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "calendar")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Colors.tint)
                        Txt(daysPhrase, variant: .bodyEmphasized, color: .tint)
                    }

                    AppButton(title: saved ? "Saved ✓" : "Save countdown", kind: .primary) { save() }
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        if let config = WidgetSharedStore.readCountdown() {
            date = config.targetDate
            label = config.label
        }
    }

    private func save() {
        WidgetSharedStore.writeCountdown(CountdownConfig(targetDate: date, label: label))
        WidgetCenter.shared.reloadAllTimelines()
        saved = true
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}

#if DEBUG
#Preview {
    ScrollView { DayCountdownSettingsSection().padding() }
        .background(Theme.Colors.background)
}
#endif
