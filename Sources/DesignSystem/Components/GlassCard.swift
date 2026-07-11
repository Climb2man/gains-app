import SwiftUI

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = Theme.Radius.card
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(Theme.Spacing.lg)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 20, x: 0, y: 10)
    }
}
