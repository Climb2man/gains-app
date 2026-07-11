import SwiftUI

struct MetricStatStrip: View {
    struct Item: Hashable {
        let label: String
        let value: String
        var unit: String? = nil
    }

    let items: [Item]

    init(items: [Item]) { self.items = items }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                cell(item)
                if index < items.count - 1 { hairline }
            }
        }
    }

    private func cell(_ item: Item) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(item.label.uppercased())
                .font(Theme.Font.footnote)
                .tracking(0.5)
                .foregroundStyle(Theme.Colors.labelSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(item.value)
                    .font(Theme.Font.statNumber)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : Theme.Motion.stepTransition, value: item.value)
                    .foregroundStyle(Theme.Colors.label)

                if let unit = item.unit {
                    Text(unit)
                        .font(Theme.Font.footnote)
                        .foregroundStyle(Theme.Colors.labelTertiary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var hairline: some View {
        Rectangle()
            .fill(Theme.Colors.separator)
            .frame(width: 1, height: 24)
    }
}

#if DEBUG
#Preview {
    VStack(spacing: Theme.Spacing.xl) {
        MetricStatStrip(items: [
            .init(label: "Avg", value: "62", unit: "%"),
            .init(label: "Min", value: "41", unit: "%"),
            .init(label: "Max", value: "88", unit: "%"),
        ])

        MetricStatStrip(items: [
            .init(label: "Avg", value: "2,140", unit: "kcal"),
            .init(label: "Latest", value: "1,980", unit: "kcal"),
            .init(label: "Δ vs typical", value: "−160", unit: "kcal"),
        ])

        MetricStatStrip(items: [
            .init(label: "Latest", value: "184.2", unit: "lb"),
            .init(label: "Δ", value: "−1.6", unit: "lb"),
        ])
    }
    .padding(Theme.Spacing.lg)
    .background(Theme.Colors.background)
}
#endif
