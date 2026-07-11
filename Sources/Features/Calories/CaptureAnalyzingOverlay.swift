import SwiftUI

struct CaptureAnalyzingOverlay: View {
    let label: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
            VStack(spacing: Theme.Spacing.md) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.Colors.tint)
                Txt(label, variant: .bodyEmphasized, center: true)
                Txt("This is an estimate you can edit.",
                    variant: .footnote, color: .labelSecondary, center: true)
            }
            .padding(Theme.Spacing.xl)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .fill(Theme.Colors.surface)
            )
            .padding(Theme.Spacing.xxl)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

#if DEBUG
#Preview("Analyzing") {
    CaptureAnalyzingOverlay(label: "Reading your photo")
        .background(Theme.Colors.background)
}
#endif
