import SwiftUI

struct InsightCard: View {
    let icon: String
    let title: String
    let message: String
    var accent: Color = Theme.Chart.activity

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
                Text(title)
                    .font(Theme.Font.bodyEmphasized)
                    .foregroundStyle(Theme.Colors.label)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.labelTertiary)
            }
            Text(message)
                .font(Theme.Font.subhead)
                .foregroundStyle(Theme.Colors.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.Colors.surface))
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 3)
    }
}
