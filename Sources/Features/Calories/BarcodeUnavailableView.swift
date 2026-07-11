import SwiftUI
import UIKit

struct BarcodeUnavailableView: View {
    let reason: BarcodeScanViewModel.Unavailable
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: symbol)
                .font(.system(size: 40))
                .foregroundStyle(Theme.Colors.labelTertiary)
            Txt(title, variant: .title2, center: true)
            Txt(message, variant: .footnote, color: .labelSecondary, center: true)

            VStack(spacing: Theme.Spacing.sm) {
                if reason == .permissionDenied {
                    Button(action: openSettings) {
                        Txt("Open Settings", variant: .bodyEmphasized, color: .onTint, center: true)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                                    .fill(Theme.Colors.tint)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Button(action: onDismiss) {
                    Txt("Type the food instead", variant: .body, color: .tint, center: true)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, Theme.Spacing.sm)
        }
        .padding(Theme.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        reason == .permissionDenied ? "lock.slash" : "camera.metering.none"
    }

    private var title: String {
        reason == .permissionDenied ? "Camera access is off" : "Scanning isn't available here"
    }

    private var message: String {
        switch reason {
        case .permissionDenied:
            "Allow camera access for Gains in Settings to scan a barcode, or type the food in plain English."
        case .noCamera:
            "This device has no camera available for scanning. You can still type the food in plain English."
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#if DEBUG
#Preview("No camera") {
    BarcodeUnavailableView(reason: .noCamera, onDismiss: {})
        .background(Theme.Colors.background)
}

#Preview("Permission denied") {
    BarcodeUnavailableView(reason: .permissionDenied, onDismiss: {})
        .background(Theme.Colors.background)
}
#endif
