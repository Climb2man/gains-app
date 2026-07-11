import SwiftUI

struct RecoveryCalendarCard: View {
    /// Daily recovery % (0–100), oldest → newest.
    let values: [Double]

    private let weeks = 18
    private let cell: CGFloat = 12
    private let gap: CGFloat = 3

    var body: some View {
        let window = Array(values.suffix(weeks * 7))
        let pad = max(0, weeks * 7 - window.count)
        let cells: [Double?] = Array(repeating: nil, count: pad) + window.map { Optional($0) }

        Card(metricAccent: Theme.Chart.recovery) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                WhoopSectionTitle(icon: "calendar", title: "Recovery calendar", color: Theme.Chart.recovery)
                Txt("Your recovery day by day. Each square is a day; deeper means more recovered.",
                    variant: .footnote, color: .labelSecondary)

                HStack(spacing: gap) {
                    ForEach(0..<weeks, id: \.self) { col in
                        VStack(spacing: gap) {
                            ForEach(0..<7, id: \.self) { row in
                                let idx = col * 7 + row
                                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                    .fill(tint(cells.indices.contains(idx) ? cells[idx] : nil))
                                    .frame(width: cell, height: cell)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                legend
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recovery calendar heatmap of your recent daily recovery percentage.")
    }

    private var legend: some View {
        HStack(spacing: gap) {
            Txt("Less", variant: .footnote, color: .labelTertiary)
            ForEach([0.2, 0.4, 0.6, 0.8, 1.0], id: \.self) { level in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(Theme.Chart.recovery.opacity(0.12 + level * 0.88))
                    .frame(width: cell, height: cell)
            }
            Txt("More", variant: .footnote, color: .labelTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// Pale → saturated recovery-cyan by recovery %; an absent day is the faint field background.
    private func tint(_ recovery: Double?) -> Color {
        guard let recovery else { return Theme.Colors.fieldBackground }
        let t = min(1, max(0, recovery / 100))
        return Theme.Chart.recovery.opacity(0.12 + t * 0.88)
    }
}

#if DEBUG
#Preview("Recovery calendar") {
    ScrollView {
        RecoveryCalendarCard(values: SampleData.recoveryCalendar)
            .padding()
    }
    .background(Theme.Colors.background)
}
#endif
