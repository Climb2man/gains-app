import SwiftUI

struct StatRingCard: View {
    let label: String
    let value: String
    let percent: String
    let progress: Double
    let color: Color

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Theme.Font.subhead.weight(.medium))
                    .foregroundStyle(Theme.Colors.labelSecondary)
                Text(value)
                    .font(Theme.Font.statNumber)
                    .foregroundStyle(Theme.Colors.label)
                Text(percent)
                    .font(Theme.Font.footnote.weight(.semibold))
                    .foregroundStyle(color)
            }
            Spacer(minLength: Theme.Spacing.sm)
            GradientRing(progress: progress, title: "",
                         gradient: [color, color], track: Theme.Colors.fieldBackground,
                         lineWidth: 6, size: 40)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.Colors.surface))
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 3)
    }
}
