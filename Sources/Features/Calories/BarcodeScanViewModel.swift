import Foundation
import Observation
import AVFoundation
import VisionKit

@MainActor
@Observable
final class BarcodeScanViewModel {
    /// Where the scan flow is right now: the single source of truth the view renders.
    enum Phase: Equatable {
        /// Resolving whether scanning is possible on this device (availability + camera permission).
        case checking
        /// Live scanning; waiting for the on-device reader to recognize a barcode.
        case scanning
        /// Looking the scanned `code` up in Open Food Facts (only the number left the device).
        case looking(code: String)
        /// A confident OFF product resolved: ready to log (the view shows a confirm card).
        case found(item: LoggedFoodItem)
        /// OFF had no product for `code`: offer the nutrition-label photo fallback.
        case notFound(code: String)
        /// A captured label image is being analyzed by the vision lane (single base64 call).
        case analyzingLabel
        /// Scanning can't run here (Simulator, no camera, or permission denied). `reason` is shown.
        case unavailable(reason: Unavailable)
    }

    /// Why scanning is unavailable: drives a specific, friendly message + the right affordance.
    enum Unavailable: Equatable {
        /// No supported camera / scanner (e.g. the iOS Simulator). Offer manual barcode entry.
        case noCamera
        /// Camera permission denied or restricted. Offer a jump to Settings.
        case permissionDenied
    }

    private(set) var phase: Phase = .checking
    /// User-facing note for a failed lookup/analysis (e.g. "Couldn't reach the product database").
    /// Never holds a key or PHI.
    private(set) var notice: String?

    private let offClient: any OpenFoodFactsClient
    /// Shared vision lane (FoodCaptureContract), used only for the label fallback: when an OFF lookup
    /// misses, the user photographs the nutrition label and we call `analyzePackage`. `nil` hides the
    /// fallback and keeps the barcode flow self-contained.
    private let vision: (any FoodVisionService)?
    /// Bias + enabled micronutrients passed through to the label-photo fallback so its estimate leans
    /// consistently with the rest of the log.
    private let bias: CalorieBias
    private let micronutrients: MicronutrientToggles
    /// Camera-authorization seam (injectable so previews/tests don't touch AVFoundation).
    private let cameraAuthorization: () -> AVAuthorizationStatus
    private let requestCameraAccess: () async -> Bool
    /// Override for scanner availability. `nil` (the default) uses the real VisionKit check, evaluated
    /// inside the @MainActor methods so it never touches a MainActor API from a nonisolated
    /// default-argument context. Previews/tests pass `false` to force the unavailable path.
    private let scannerAvailableOverride: Bool?

    init(
        offClient: any OpenFoodFactsClient = HTTPOpenFoodFactsClient(),
        vision: (any FoodVisionService)? = nil,
        bias: CalorieBias = .balanced,
        micronutrients: MicronutrientToggles = .off,
        scannerAvailable: Bool? = nil,
        cameraAuthorization: @escaping () -> AVAuthorizationStatus = {
            AVCaptureDevice.authorizationStatus(for: .video)
        },
        requestCameraAccess: @escaping () async -> Bool = {
            await AVCaptureDevice.requestAccess(for: .video)
        }
    ) {
        self.offClient = offClient
        self.vision = vision
        self.bias = bias
        self.micronutrients = micronutrients
        self.scannerAvailableOverride = scannerAvailable
        self.cameraAuthorization = cameraAuthorization
        self.requestCameraAccess = requestCameraAccess
    }

    /// Resolve scanner availability: the test/preview override when present, else the real VisionKit
    /// check. @MainActor-safe (the VisionKit class properties are MainActor-isolated).
    private var isScannerAvailable: Bool {
        if let scannerAvailableOverride { return scannerAvailableOverride }
        return DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    /// Resolve availability + permission, then move to `.scanning` or `.unavailable`. Safe to call on
    /// `.task`/`.onAppear`. On the Simulator (no scanner support) this lands on `.unavailable(.noCamera)`,
    /// never a crash.
    func start() async {
        guard isScannerAvailable else {
            phase = .unavailable(reason: .noCamera)
            return
        }
        switch cameraAuthorization() {
        case .authorized:
            phase = .scanning
        case .notDetermined:
            let granted = await requestCameraAccess()
            phase = granted ? .scanning : .unavailable(reason: .permissionDenied)
        case .denied, .restricted:
            phase = .unavailable(reason: .permissionDenied)
        @unknown default:
            phase = .unavailable(reason: .permissionDenied)
        }
    }

    /// The scanner reported it became unavailable mid-session (permission revoked, etc).
    func scannerBecameUnavailable() {
        if case .scanning = phase {
            phase = .unavailable(reason: .permissionDenied)
        }
    }

    /// Handle a recognized barcode number from the on-device reader. Looks it up in Open Food Facts
    /// (only the number egresses). A confident product → `.found`; a clean miss → `.notFound` (offer the
    /// label-photo fallback); a transport failure → `.notFound` too (the user can still photo the label).
    func handleScanned(_ code: String) async {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.allSatisfy(\.isNumber) else { return }
        guard case .scanning = phase else { return }

        phase = .looking(code: trimmed)
        notice = nil
        do {
            if let match = try await offClient.product(barcode: trimmed) {
                phase = .found(item: match.item)
            } else {
                phase = .notFound(code: trimmed)
            }
        } catch {
            notice = "Couldn't reach the product database. Try the nutrition label instead."
            phase = .notFound(code: trimmed)
        }
    }

    /// True when the vision lane is wired in, so the view can offer the photo fallback button. When
    /// false, the fallback affordance is hidden (scan again / manual entry only).
    var canAnalyzeLabel: Bool { vision != nil }

    /// Analyze a captured nutrition-label image via the shared vision lane's `analyzePackage`: the image
    /// is persisted on-device and one base64 call goes out on the user's key. On success the first item
    /// lands in `.found` for confirmation; `.missingKey` routes to Settings, any other failure shows a note.
    func analyzeLabel(imageData: Data) async {
        guard let vision else { return }
        phase = .analyzingLabel
        notice = nil
        do {
            let result = try await vision.analyzePackage(
                imageJPEG: imageData, bias: bias, micronutrients: micronutrients
            )
            if let first = result.items.first {
                phase = .found(item: first)
            } else {
                notice = "Couldn't read that label. Try again, or add the food by typing it."
                phase = .scanning
            }
        } catch FoodCaptureError.missingKey {
            notice = FoodCaptureError.missingKey.userMessage
            phase = .scanning
        } catch {
            notice = "Couldn't read that label. Try again, or add the food by typing it."
            phase = .scanning
        }
    }

    /// Discard the current result and scan again (after a found/not-found, or to retry).
    func scanAgain() {
        notice = nil
        phase = isScannerAvailable ? .scanning : .unavailable(reason: .noCamera)
    }
}
