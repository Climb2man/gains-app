import SwiftUI

enum AppButtonKind { case primary, secondary, tertiary, destructive }

struct AppButton: View {
    let title: String
    var icon: String? = nil
    var kind: AppButtonKind = .primary
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                if let icon { Image(systemName: icon).font(.system(size: 15, weight: .semibold)) }
                Text(title).font(Theme.Font.bodyEmphasized)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(fg)
            .background(bg, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).strokeBorder(border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var fg: Color {
        switch kind {
        case .primary, .destructive: return Theme.Colors.onTint
        case .secondary: return Theme.Colors.label
        case .tertiary: return Theme.Colors.tint
        }
    }
    private var bg: Color {
        switch kind {
        case .primary: return Theme.Colors.tint
        case .destructive: return Theme.Colors.danger
        case .secondary: return Theme.Colors.fieldBackground
        case .tertiary: return .clear
        }
    }
    private var border: Color { kind == .tertiary ? Theme.Colors.separator : .clear }
}

struct IconButton: View {
    let systemName: String
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Colors.label)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Theme.Colors.fieldBackground))
        }
        .buttonStyle(.plain)
    }
}

struct PillButton: View {
    let title: String
    var selected: Bool = false
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Font.subhead.weight(.medium))
                .foregroundStyle(selected ? Theme.Colors.onTint : Theme.Colors.labelSecondary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Capsule().fill(selected ? Theme.Colors.label : Theme.Colors.fieldBackground))
        }
        .buttonStyle(.plain)
    }
}

struct FAB: View {
    var systemName: String = "plus"
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.Colors.onTint)
                .frame(width: 56, height: 56)
                .background(Theme.Colors.tint, in: .circle)
                .overlay(Circle().stroke(Theme.Colors.surface, lineWidth: 3))
                .shadow(color: Theme.Colors.tint.opacity(0.4), radius: 10, y: 6)
        }
        .buttonStyle(.plain)
    }
}
