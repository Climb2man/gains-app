import SwiftUI

struct BarcodeNotFoundView: View {
    let code: String
    let notice: String?
    let canAnalyzeLabel: Bool
    let onAnalyzeLabel: (Data) -> Void
    let onScanAgain: () -> Void

    @State private var isPickingLabel = false

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.Colors.labelTertiary)
                Txt("No product found", variant: .title2, center: true)
                Txt("We couldn't find barcode \(code) in the open product database.",
                    variant: .footnote, color: .labelSecondary, center: true)
                if let notice, !notice.isEmpty {
                    Txt(notice, variant: .footnote, color: .warning, center: true)
                }
            }

            VStack(spacing: Theme.Spacing.sm) {
                if canAnalyzeLabel {
                    Button { isPickingLabel = true } label: {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "doc.text.viewfinder")
                            Txt("Photograph the nutrition label", variant: .bodyEmphasized, color: .onTint)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                                .fill(Theme.Colors.tint)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Photograph the nutrition label to estimate macros")
                }

                Button(action: onScanAgain) {
                    Txt("Scan again", variant: .body, color: .tint, center: true)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $isPickingLabel) {
            LabelImagePicker(
                onCapture: { data in
                    isPickingLabel = false
                    onAnalyzeLabel(data)
                },
                onCancel: { isPickingLabel = false }
            )
            .ignoresSafeArea()
        }
    }
}

#if DEBUG
#Preview("Not found") {
    BarcodeNotFoundView(
        code: "0123456789012",
        notice: nil,
        canAnalyzeLabel: true,
        onAnalyzeLabel: { _ in },
        onScanAgain: {}
    )
    .background(Theme.Colors.background)
}
#endif
