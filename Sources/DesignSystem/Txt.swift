import SwiftUI

struct Txt: View {
    enum Variant {
        case largeTitle, title1, title2, body, bodyEmphasized, callout, subhead, footnote
        /// Small uppercase section / field header. Adds letter-tracking and uppercasing (in `body`).
        case sectionHeader

        var font: Font {
            switch self {
            case .largeTitle: return Theme.Font.largeTitle
            case .title1: return Theme.Font.title1
            case .title2: return Theme.Font.title2
            case .body: return Theme.Font.body
            case .bodyEmphasized: return Theme.Font.bodyEmphasized
            case .callout: return Theme.Font.callout
            case .subhead: return Theme.Font.subhead
            case .footnote: return Theme.Font.footnote
            case .sectionHeader: return Theme.Font.sectionHeader
            }
        }
    }

    enum ColorKey {
        case label, labelSecondary, labelTertiary, tint, onTint, success, warning, danger

        var color: Color {
            switch self {
            case .label: return Theme.Colors.label
            case .labelSecondary: return Theme.Colors.labelSecondary
            case .labelTertiary: return Theme.Colors.labelTertiary
            case .tint: return Theme.Colors.tint
            case .onTint: return Theme.Colors.onTint
            case .success: return Theme.Colors.success
            case .warning: return Theme.Colors.warning
            case .danger: return Theme.Colors.danger
            }
        }
    }

    private let text: String
    private let variant: Variant
    private let colorKey: ColorKey
    private let center: Bool

    init(_ text: String, variant: Variant = .body, color: ColorKey = .label, center: Bool = false) {
        self.text = text
        self.variant = variant
        self.colorKey = color
        self.center = center
    }

    var body: some View {
        Text(text)
            .tracking(variant == .sectionHeader ? 0.6 : 0)
            .font(variant.font)
            .textCase(variant == .sectionHeader ? Text.Case.uppercase : nil)
            .foregroundStyle(colorKey.color)
            .multilineTextAlignment(center ? .center : .leading)
            .frame(maxWidth: center ? .infinity : nil, alignment: center ? .center : .leading)
    }
}
