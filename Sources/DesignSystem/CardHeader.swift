import SwiftUI

struct CardHeader: View {
    let title: String
    var icon: String?
    var sourceLabel: String?
    var showsChevron: Bool = false

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Colors.labelSecondary)
            }
            Txt(title, variant: .footnote, color: .labelSecondary)
            Spacer(minLength: 0)
            if let sourceLabel {
                Txt(sourceLabel, variant: .footnote, color: .labelTertiary)
            }
            if showsChevron {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Colors.labelTertiary)
            }
        }
    }
}
