import SwiftUI

struct BarcodeScanStatusView: View {
    let symbol: String
    let title: String
    var subtitle: String?
    var showsSpinner: Bool = false

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Theme.Colors.tint)
            Txt(title, variant: .title2, center: true)
            if let subtitle {
                Txt(subtitle, variant: .footnote, color: .labelSecondary, center: true)
            }
            if showsSpinner {
                ProgressView()
                    .tint(Theme.Colors.tint)
                    .padding(.top, Theme.Spacing.xs)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(subtitle.map { "\(title), \($0)" } ?? title)
    }
}

#if DEBUG
#Preview("Status") {
    BarcodeScanStatusView(
        symbol: "barcode.viewfinder",
        title: "Looking up barcode…",
        subtitle: "0123456789012",
        showsSpinner: true
    )
    .background(Theme.Colors.background)
}
#endif
