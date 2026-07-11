import SwiftUI

struct RecoveryHeatmap: View {
    /// One cell per day, oldest → newest. `pct` is the day's recovery % (0–100); nil = no reading.
    let days: [Day]
    /// Tapping a populated day passes its `date` key back.
    var onTapDay: (String) -> Void = { _ in }

    /// A calendar cell: YYYY-MM-DD key + recovery % (nil when no reading).
    struct Day: Identifiable, Equatable {
        let date: String
        let pct: Double?
        var id: String { date }
    }

    private static let rows = 7
    private let cell: CGFloat = 15
    private let gap: CGFloat = 4

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        let layout = Array(
            repeating: GridItem(.fixed(cell), spacing: gap),
            count: Self.rows
        )

        ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: layout, spacing: gap) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    cellView(day, column: index / Self.rows)
                }
            }
            .padding(.vertical, Theme.Spacing.xs)
        }
        .onAppear {
            guard !reduceMotion else { appeared = true; return }
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
        }
    }

    @ViewBuilder
    private func cellView(_ day: Day, column: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        let fill: Color = day.pct.map { Theme.Heatmap.recoveryRamp($0) } ?? Theme.Colors.surface2

        Button {
            if day.pct != nil { onTapDay(day.date) }
        } label: {
            shape
                .fill(fill)
                .frame(width: cell, height: cell)
                .overlay { shape.stroke(Theme.Colors.separator, lineWidth: 0.5) }
        }
        .buttonStyle(.plain)
        .disabled(day.pct == nil)
        .opacity(appeared ? 1 : 0)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.4).delay(Double(column) * 0.012),
            value: appeared
        )
        .accessibilityLabel(accessibilityLabel(day))
    }

    private func accessibilityLabel(_ day: Day) -> String {
        guard let pct = day.pct else { return "\(day.date), no reading" }
        return "\(day.date), recovery \(Int(pct.rounded())) percent"
    }
}

#if DEBUG
#Preview {
    let days: [RecoveryHeatmap.Day] = (0..<84).map { i in
        let pct: Double? = (i % 11 == 0) ? nil : Double((i * 37) % 100)
        return .init(date: String(format: "2026-%02d-%02d", (i / 28) + 1, (i % 28) + 1), pct: pct)
    }
    return RecoveryHeatmap(days: days)
        .padding()
        .background(Theme.Colors.surface)
}
#endif
