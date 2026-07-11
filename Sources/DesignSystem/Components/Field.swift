import SwiftUI

struct FormField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var isSecure: Bool = false
    var keyboard: UIKeyboardType = .default
    var autocap: TextInputAutocapitalization = .never

    init(
        label: String,
        text: Binding<String>,
        placeholder: String = "",
        isSecure: Bool = false,
        keyboard: UIKeyboardType = .default,
        autocap: TextInputAutocapitalization = .never
    ) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.isSecure = isSecure
        self.keyboard = keyboard
        self.autocap = autocap
    }

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Txt(label, variant: .footnote, color: .labelSecondary)
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(Theme.Font.body)
            .foregroundStyle(Theme.Colors.label)
            .keyboardType(keyboard)
            .textInputAutocapitalization(isSecure ? .never : autocap)
            .autocorrectionDisabled(true)
            .focused($focused)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Colors.fieldBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.Colors.tint, lineWidth: focused ? 2 : 0)
            )
            .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}

#if DEBUG
private struct FieldPreview: View {
    @State private var email = ""
    @State private var secret = ""
    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            FormField(label: "Whoop email", text: $email,
                       placeholder: "you@example.com", keyboard: .emailAddress)
            FormField(label: "Whoop password", text: $secret,
                       placeholder: "Your Whoop password", isSecure: true)
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.background)
    }
}

#Preview("FormField") { FieldPreview() }
#endif
