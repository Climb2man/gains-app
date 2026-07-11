import SwiftUI

struct TappableCard<Content: View>: View {
    var onPress: (() -> Void)?
    var accessibilityLabel: String?
    @ViewBuilder var content: Content

    var body: some View {
        if let onPress {
            Button(action: onPress) {
                Card { content }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(accessibilityLabel ?? "")
        } else {
            Card { content }
        }
    }
}
