import SwiftUI

struct SurfaceCard<Content: View>: View {
    var padding: CGFloat = Theme.Spacing.lg
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.Colors.surface))
            .compositingGroup()
            .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 3)
    }
}

struct ActionCard: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var accent: Color = Theme.Colors.tint
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            SurfaceCard {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accent).frame(width: 36, height: 36)
                        .background(Circle().fill(accent.opacity(0.14)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(Theme.Font.bodyEmphasized).foregroundStyle(Theme.Colors.label)
                        if let subtitle { Text(subtitle).font(Theme.Font.footnote).foregroundStyle(Theme.Colors.labelTertiary) }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Colors.labelTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct EmptyStateCard: View {
    let icon: String
    let title: String
    let message: String
    var body: some View {
        SurfaceCard {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon).font(.system(size: 28)).foregroundStyle(Theme.Colors.labelTertiary)
                Text(title).font(Theme.Font.bodyEmphasized).foregroundStyle(Theme.Colors.label)
                Text(message).font(Theme.Font.subhead).foregroundStyle(Theme.Colors.labelSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.lg)
        }
    }
}

struct ListRow: View {
    let title: String
    var value: String? = nil
    var leadingIcon: String? = nil
    var showsChevron: Bool = true
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            if let leadingIcon {
                Image(systemName: leadingIcon).font(.system(size: 16)).foregroundStyle(Theme.Colors.tint).frame(width: 24)
            }
            Text(title).font(Theme.Font.body).foregroundStyle(Theme.Colors.label)
            Spacer(minLength: 0)
            if let value { Text(value).font(Theme.Font.body).foregroundStyle(Theme.Colors.labelSecondary) }
            if showsChevron {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Colors.labelTertiary)
            }
        }
        .padding(.vertical, Theme.Spacing.md)
    }
}

struct SettingsRow: View {
    let title: String
    @Binding var isOn: Bool
    var icon: String? = nil
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            if let icon {
                Image(systemName: icon).font(.system(size: 16)).foregroundStyle(Theme.Colors.tint).frame(width: 24)
            }
            Text(title).font(Theme.Font.body).foregroundStyle(Theme.Colors.label)
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().tint(Theme.Colors.tint)
        }
        .padding(.vertical, Theme.Spacing.sm)
    }
}
