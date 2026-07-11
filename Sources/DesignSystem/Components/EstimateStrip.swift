import SwiftUI

struct EstimateStrip: View {
    let label: String
    let value: String
    let unit: String
    let infoBody: String
    var icon: String = "flame.fill"
    var accent: Color = Theme.Chart.calories

    init(
        label: String,
        value: String,
        unit: String,
        infoBody: String,
        icon: String = "flame.fill",
        accent: Color = Theme.Chart.calories
    ) {
        self.label = label
        self.value = value
        self.unit = unit
        self.infoBody = infoBody
        self.icon = icon
        self.accent = accent
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 36, height: 36)
                .background(Circle().fill(accent.opacity(0.14)))

            VStack(alignment: .leading, spacing: 2) {
                Txt(label, variant: .footnote, color: .labelSecondary)
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Text(value)
                        .font(Theme.Font.statNumber)
                        .foregroundStyle(Theme.Colors.label)
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : .snappy, value: value)
                    Text(unit)
                        .font(Theme.Font.subhead)
                        .foregroundStyle(Theme.Colors.labelSecondary)
                }
            }

            Spacer(minLength: Theme.Spacing.sm)

            InfoDisclosure(title: label, body: infoBody)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.fieldBackground)
        )
    }
}

#if DEBUG
#Preview("EstimateStrip") {
    VStack(spacing: Theme.Spacing.lg) {
        EstimateStrip(
            label: "Resting energy",
            value: "1,742",
            unit: "cal/day",
            infoBody: "An estimate from your profile (sex, age, height, weight), not a medical "
                + "measurement. It updates your Energy Balance as you edit these basics."
        )
    }
    .padding(Theme.Spacing.lg)
    .background(Theme.Colors.background)
}
#endif
