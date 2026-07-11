import SwiftUI
import Vision
import VisionKit

struct BarcodeScannerRepresentable: UIViewControllerRepresentable {
    /// Called once, with the first barcode read; the parent stops scanning on first hit.
    let onScan: (String) -> Void
    /// Called if VisionKit reports it became unavailable after starting (e.g. camera permission revoked
    /// mid-session) so the host can flip to the unavailable state instead of showing a frozen preview.
    let onUnavailable: () -> Void

    /// The barcode symbologies we accept: the common retail set Open Food Facts indexes by.
    private static let symbologies: [VNBarcodeSymbology] = [.upce, .ean8, .ean13, .code128, .code39]

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: Self.symbologies)],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !context.coordinator.isScanning {
            context.coordinator.isScanning = (try? scanner.startScanning()) != nil
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
        coordinator.isScanning = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onUnavailable: onUnavailable)
    }

    /// Bridges the UIKit delegate callbacks back to the SwiftUI closures. Fires `onScan` exactly once
    /// (guarded by `hasReported`) so a rapidly re-recognized barcode can't double-log.
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        private let onUnavailable: () -> Void
        /// Whether `startScanning()` is currently running. Drives the idempotent start in `update…`.
        var isScanning = false
        /// One-shot guard: we report the first valid barcode and ignore the rest of the session.
        private var hasReported = false

        init(onScan: @escaping (String) -> Void, onUnavailable: @escaping () -> Void) {
            self.onScan = onScan
            self.onUnavailable = onUnavailable
        }

        /// A new recognized item appeared. Take the first barcode with a non-empty payload string.
        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            report(from: addedItems)
        }

        /// VisionKit became unavailable (e.g. permission revoked). Tell the host to show fallback UI.
        func dataScanner(
            _ dataScanner: DataScannerViewController,
            becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable
        ) {
            onUnavailable()
        }

        private func report(from items: [RecognizedItem]) {
            guard !hasReported else { return }
            for case let .barcode(barcode) in items {
                guard let payload = barcode.payloadStringValue,
                      !payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                hasReported = true
                onScan(payload.trimmingCharacters(in: .whitespacesAndNewlines))
                return
            }
        }
    }
}
