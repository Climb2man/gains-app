import SwiftUI

struct PlaceholderScreen: View {
    let title: String
    let subtitle: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text(title)
                    .font(Theme.Font.largeTitle)
                    .foregroundStyle(Theme.Colors.label)
                    .padding(.top, Theme.Spacing.xl)
                Card {
                    Text(subtitle)
                        .font(Theme.Font.subhead)
                        .foregroundStyle(Theme.Colors.labelSecondary)
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Colors.background)
    }
}
