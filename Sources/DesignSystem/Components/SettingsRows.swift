import SwiftUI

/// Uppercased, kerned section heading with an optional caption below.
struct SectionCaption: View {
    let title: String
    var caption: String? = nil

    init(title: String, caption: String? = nil) {
        self.title = title
        self.caption = caption
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title.uppercased())
                .font(Theme.Font.footnote.weight(.semibold))
                .foregroundStyle(Theme.Colors.labelSecondary)
                .kerning(0.6)
                .padding(.horizontal, Theme.Spacing.xs)
            if let caption {
                Txt(caption, variant: .footnote, color: .labelTertiary)
                    .padding(.horizontal, Theme.Spacing.xs)
            }
        }
    }
}

/// A rounded card surface holding a VStack of rows with hairline dividers between them, inset so each
/// divider clears the row's icon tile. Compose `SettingsNavRow` / `SettingsValueRow` inside.
struct SettingsGroup<Content: View>: View {
    @ViewBuilder var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            _VariadicView.Tree(DividedRows()) {
                content
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .cardShadow()
    }
}

/// Lays child rows in a VStack with an inset hairline between each pair. Uses `_VariadicView` so the
/// divider logic lives here rather than at every call site.
private struct DividedRows: _VariadicView.MultiViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        let last = children.last?.id
        ForEach(children) { child in
            child
            if child.id != last {
                Rectangle()
                    .fill(Theme.Colors.separator)
                    .frame(height: 1)
                    .padding(.leading, Theme.Layout.settingsRowInset)
            }
        }
    }
}

/// A tappable settings row: tinted icon, title (with optional subtitle), and a trailing chevron.
/// The `destructive` variant tints the icon and title in danger; the caller's `action` owns the tap.
struct SettingsNavRow: View {
    let icon: String
    var accent: Color = Theme.Colors.tint
    let title: String
    var subtitle: String? = nil
    var destructive: Bool = false
    let action: () -> Void

    init(
        icon: String,
        accent: Color = Theme.Colors.tint,
        title: String,
        subtitle: String? = nil,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.accent = accent
        self.title = title
        self.subtitle = subtitle
        self.destructive = destructive
        self.action = action
    }

    private var tint: Color { destructive ? Theme.Colors.danger : accent }
    private var titleColor: Color { destructive ? Theme.Colors.danger : Theme.Colors.label }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                SettingsIcon(icon: icon, accent: tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.Font.body)
                        .foregroundStyle(titleColor)
                    if let subtitle {
                        Txt(subtitle, variant: .footnote, color: .labelSecondary)
                    }
                }
                Spacer(minLength: Theme.Spacing.sm)
                Image(systemName: "chevron.forward")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.labelTertiary)
            }
            .padding(.vertical, Theme.Spacing.md + 2)
            .padding(.horizontal, Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableRowStyle())
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [title]
        if let subtitle { parts.append(subtitle) }
        return parts.joined(separator: ", ")
    }
}

/// A non-tappable settings row: tinted icon, title, trailing value, an optional trailing status view
/// (e.g. a soft-success pill), and an optional chevron. `disabled` dims the row.
struct SettingsValueRow<Status: View>: View {
    let icon: String
    var accent: Color = Theme.Colors.tint
    let title: String
    var value: String? = nil
    var chevron: Bool = false
    var disabled: Bool = false
    @ViewBuilder var status: Status

    init(
        icon: String,
        accent: Color = Theme.Colors.tint,
        title: String,
        value: String? = nil,
        chevron: Bool = false,
        disabled: Bool = false,
        @ViewBuilder status: () -> Status = { EmptyView() }
    ) {
        self.icon = icon
        self.accent = accent
        self.title = title
        self.value = value
        self.chevron = chevron
        self.disabled = disabled
        self.status = status()
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            SettingsIcon(icon: icon, accent: accent)
            Text(title)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Colors.label)
            Spacer(minLength: Theme.Spacing.sm)
            if let value {
                Txt(value, variant: .subhead, color: .labelSecondary)
            }
            status
            if chevron {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.labelTertiary)
            }
        }
        .padding(.vertical, Theme.Spacing.md + 2)
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(disabled ? 0.5 : 1)
        .accessibilityElement(children: .combine)
    }
}

/// The shared tinted circular icon tile, sized to align with `Theme.Layout.settingsRowInset`.
private struct SettingsIcon: View {
    let icon: String
    let accent: Color

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(accent)
            .frame(width: 30, height: 30)
            .background(Circle().fill(accent.opacity(0.14)))
    }
}

#if DEBUG
#Preview("SettingsRows") {
    ScrollView {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            SectionCaption(title: "Your record",
                               caption: "Everything here lives only on this device.")
            SettingsGroup {
                SettingsNavRow(icon: "person.crop.circle", accent: Theme.Colors.tint,
                                    title: "Profile", subtitle: "Male · 20 · 5'10\" · 206 lb") {}
                SettingsValueRow(icon: "ruler", accent: Theme.Colors.tint,
                                      title: "Measurement system", value: "Imperial", disabled: true)
                SettingsValueRow(icon: "waveform.path.ecg", accent: Theme.Chart.recovery,
                                      title: "Whoop", value: "Linked")
            }
            SettingsGroup {
                SettingsNavRow(icon: "trash", accent: Theme.Colors.danger,
                                    title: "Delete my data", destructive: true) {}
            }
        }
        .padding(Theme.Spacing.lg)
    }
    .background(Theme.Colors.background)
}
#endif
