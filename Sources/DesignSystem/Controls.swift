import SwiftUI

struct PrimaryButton: View {
    let title: String
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Txt(title, variant: .bodyEmphasized, color: disabled ? .labelTertiary : .onTint, center: true)
        }
        .buttonStyle(FilledButtonStyle(disabled: disabled))
        .disabled(disabled)
    }
}

struct SecondaryButton: View {
    let title: String
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Txt(title, variant: .bodyEmphasized, color: disabled ? .labelTertiary : .tint, center: true)
        }
        .buttonStyle(SoftButtonStyle(disabled: disabled))
        .disabled(disabled)
    }
}

private struct FilledButtonStyle: ButtonStyle {
    let disabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        let background: Color = disabled
            ? Theme.Colors.fieldBackground
            : (configuration.isPressed ? Theme.Colors.tintPressed : Theme.Colors.tint)
        return configuration.label
            .padding(.vertical, Theme.Spacing.md + 2)
            .padding(.horizontal, Theme.Spacing.xl)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(background)
            )
    }
}

private struct SoftButtonStyle: ButtonStyle {
    let disabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        let background: Color = disabled
            ? Theme.Colors.fieldBackground
            : (configuration.isPressed ? Theme.Colors.separator : Theme.Colors.fieldBackground)
        return configuration.label
            .padding(.vertical, Theme.Spacing.md + 2)
            .padding(.horizontal, Theme.Spacing.xl)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(background)
            )
    }
}

struct Field: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboard: UIKeyboardType = .default
    var secure: Bool = false
    var autocapitalization: TextInputAutocapitalization = .sentences

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Txt(label, variant: .footnote, color: .labelSecondary)
            Group {
                if secure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(Theme.Font.body)
            .foregroundStyle(Theme.Colors.label)
            .keyboardType(keyboard)
            .textInputAutocapitalization(secure ? .never : autocapitalization)
            .autocorrectionDisabled(secure)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(Theme.Colors.fieldBackground)
            )
        }
    }
}

struct SegmentedChoice<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let label: String
        var id: Value { value }
    }

    let label: String
    let options: [Option]
    @Binding var selection: Value?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Txt(label, variant: .footnote, color: .labelSecondary)
            HStack(spacing: 2) {
                ForEach(options) { option in
                    segment(option)
                }
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(Theme.Colors.fieldBackground)
            )
        }
    }

    @ViewBuilder
    private func segment(_ option: Option) -> some View {
        let selected = option.value == selection
        Button {
            selection = option.value
        } label: {
            Text(option.label)
                .font(Theme.Font.subhead.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? Theme.Colors.label : Theme.Colors.labelSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        .fill(selected ? Theme.Colors.surface : .clear)
                        .shadow(
                            color: selected ? Color.black.opacity(0.06) : .clear,
                            radius: selected ? 16 : 0, x: 0, y: selected ? 6 : 0
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct Pill: View {
    enum Tone {
        case tint, neutral, success, warning, danger

        var background: Color {
            switch self {
            case .tint: return Theme.Colors.tintSoft
            case .neutral: return Theme.Colors.fieldBackground
            case .success: return Theme.Colors.success.opacity(0.15)
            case .warning: return Theme.Colors.warning.opacity(0.15)
            case .danger: return Theme.Colors.danger.opacity(0.15)
            }
        }

        var foreground: Color {
            switch self {
            case .tint: return Theme.Colors.tint
            case .neutral: return Theme.Colors.labelSecondary
            case .success: return Theme.Colors.success
            case .warning: return Theme.Colors.warning
            case .danger: return Theme.Colors.danger
            }
        }
    }

    let text: String
    var icon: String?
    var tone: Tone = .tint

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(text)
                .font(Theme.Font.footnote.weight(.semibold))
        }
        .foregroundStyle(tone.foreground)
        .padding(.vertical, Theme.Spacing.xs)
        .padding(.horizontal, Theme.Spacing.sm)
        .background(
            Capsule().fill(tone.background)
        )
    }
}

struct HairlineDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.Colors.separator)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}
