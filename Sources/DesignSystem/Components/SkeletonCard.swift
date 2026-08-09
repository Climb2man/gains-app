import SwiftUI

struct SkeletonCard: View {
    /// Number of ghost text lines beside the ghost ring (the last line renders shorter).
    var lines: Int = 3

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        Card {
            HStack(alignment: .center, spacing: Theme.Spacing.lg) {
                ghostRing
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    ForEach(0..<max(1, lines), id: \.self) { i in
                        ghostBlock(width: i == lines - 1 ? 0.55 : (i == 0 ? 0.9 : 0.75), height: 12)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, Theme.Spacing.xs)
        }
        .modifier(ShimmerOverlay(phase: phase, enabled: !reduceMotion))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(Theme.Motion.shimmer) { phase = 2 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }

    private var ghostRing: some View {
        Circle()
            .stroke(Theme.Colors.surface2, lineWidth: 10)
            .frame(width: 84, height: 84)
    }

    private func ghostBlock(width fraction: CGFloat, height: CGFloat) -> some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .fill(Theme.Colors.surface2)
                .frame(width: geo.size.width * fraction, height: height)
        }
        .frame(height: height)
    }
}

private struct ShimmerOverlay: ViewModifier {
    let phase: CGFloat
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.overlay {
                GeometryReader { geo in
                    LinearGradient(
                        // 0.55 was tuned for a white skeleton; on a near-black surface that reads as
                        // a strobe rather than a sheen.
                        colors: [.clear, Color.white.opacity(0.10), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.5)
                    .offset(x: phase * geo.size.width)
                }
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
                .mask(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            }
        } else {
            content
        }
    }
}

#if DEBUG
#Preview {
    VStack(spacing: Theme.Spacing.lg) {
        SkeletonCard()
        SkeletonCard(lines: 2)
    }
    .padding(Theme.Spacing.xl)
    .background(Theme.Colors.background)
}
#endif
