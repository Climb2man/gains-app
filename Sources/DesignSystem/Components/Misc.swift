import SwiftUI

struct Avatar: View {
    let initials: String
    var size: CGFloat = 40
    var fill: Color = Theme.Colors.tintSoft
    var textColor: Color = Theme.Colors.tint
    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(textColor)
            .frame(width: size, height: size)
            .background(Circle().fill(fill))
    }
}

struct Chip: View {
    let text: String
    var icon: String? = nil
    var color: Color = Theme.Colors.labelSecondary
    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 11, weight: .semibold)) }
            Text(text).font(Theme.Font.footnote.weight(.medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 6)
        .background(Capsule().fill(Theme.Colors.fieldBackground))
    }
}

struct Skeleton: View {
    var width: CGFloat? = nil
    var height: CGFloat = 16
    var cornerRadius: CGFloat = Theme.Radius.sm
    @State private var shimmer = false
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Theme.Colors.fieldBackground)
            .overlay(
                LinearGradient(colors: [.clear, Theme.Colors.surface.opacity(0.6), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .offset(x: shimmer ? 200 : -200)
                    .mask(RoundedRectangle(cornerRadius: cornerRadius))
            )
            .frame(width: width, height: height)
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { shimmer = true }
            }
    }
}
