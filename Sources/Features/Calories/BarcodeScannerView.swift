import SwiftUI

struct BarcodeScannerView: View {
    @State private var model: BarcodeScanViewModel
    /// Called with a confirmed item to log (a found OFF product or an analyzed label). The host writes
    /// it to the food log and typically dismisses the sheet.
    let onLog: (LoggedFoodItem) -> Void
    let onDismiss: () -> Void

    /// Contract entry point (FoodCaptureContract): the host presents the scanner with just these two
    /// closures. Builds a default view model where OFF lookup works but the label fallback stays hidden
    /// until a vision service is injected via the other init.
    init(
        onLog: @escaping (LoggedFoodItem) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.init(model: BarcodeScanViewModel(), onLog: onLog, onDismiss: onDismiss)
    }

    /// Inject a pre-configured view model, e.g. one wired with the shared `FoodVisionService` to enable
    /// the label fallback, or a forced-unavailable model for previews/tests.
    init(
        model: BarcodeScanViewModel,
        onLog: @escaping (LoggedFoodItem) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.onLog = onLog
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.Colors.background)
                .navigationTitle("Scan barcode")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done", action: onDismiss)
                            .foregroundStyle(Theme.Colors.tint)
                    }
                }
        }
        .task { await model.start() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .checking:
            BarcodeScanStatusView(symbol: "viewfinder", title: "Preparing camera…", showsSpinner: true)
        case .scanning:
            scanningSurface
        case .looking(let code):
            BarcodeScanStatusView(
                symbol: "barcode.viewfinder",
                title: "Looking up barcode…",
                subtitle: code,
                showsSpinner: true
            )
        case .found(let item):
            BarcodeFoundCard(
                item: item,
                onLog: { onLog(item); onDismiss() },
                onScanAgain: { model.scanAgain() }
            )
        case .notFound(let code):
            BarcodeNotFoundView(
                code: code,
                notice: model.notice,
                canAnalyzeLabel: model.canAnalyzeLabel,
                onAnalyzeLabel: { data in Task { await model.analyzeLabel(imageData: data) } },
                onScanAgain: { model.scanAgain() }
            )
        case .analyzingLabel:
            BarcodeScanStatusView(
                symbol: "doc.text.viewfinder",
                title: "Reading nutrition label…",
                showsSpinner: true
            )
        case .unavailable(let reason):
            BarcodeUnavailableView(reason: reason, onDismiss: onDismiss)
        }
    }

    private var scanningSurface: some View {
        BarcodeScannerRepresentable(
            onScan: { code in Task { await model.handleScanned(code) } },
            onUnavailable: { model.scannerBecameUnavailable() }
        )
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .bottom) { scanHint }
        .accessibilityLabel("Point the camera at a product barcode")
    }

    private var scanHint: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.Colors.onTint)
            Txt("Center a product barcode in view", variant: .footnote, color: .onTint, center: true)
        }
        .padding(.vertical, Theme.Spacing.md)
        .padding(.horizontal, Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .fill(Color.black.opacity(0.55))
        )
        .padding(.bottom, Theme.Spacing.xxl)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Barcode · unavailable") {
    BarcodeScannerView(
        model: BarcodeScanViewModel(scannerAvailable: false),
        onLog: { _ in },
        onDismiss: {}
    )
}
#endif
