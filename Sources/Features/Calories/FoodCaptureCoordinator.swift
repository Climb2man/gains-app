import Foundation
import Observation

@MainActor
@Observable
final class FoodCaptureCoordinator {
    /// Which vision capture flow (if any) is presenting. Barcode is not here; it is owned end-to-end by
    /// `BarcodeScannerView` and the food-log view model.
    enum Phase: Equatable {
        case idle
        /// A capture is being analyzed (vision call in flight); show a busy state.
        case analyzing(CaptureKind)
        /// Editable estimate lines are ready to confirm before logging (photo / package).
        case reviewingEstimate(CaptureReview)
        /// A scanned menu is ready: pick the dishes you ate (grouped by section).
        case reviewingMenu(MenuReview)
        /// A non-credential error to show inline (e.g. "not a menu", "couldn't read that").
        case error(String)
    }

    /// Which entry point a review/analysis came from; drives copy and the analyzing label. Barcode is
    /// not here; its flow is owned end-to-end by `BarcodeScannerView`.
    enum CaptureKind: Equatable, Sendable {
        case photo, menu, package

        var analyzingLabel: String {
            switch self {
            case .photo: "Reading your photo"
            case .menu: "Scanning the menu"
            case .package: "Reading the label"
            }
        }
    }

    /// A set of editable estimate lines awaiting the user's confirmation (photo / package / barcode).
    struct CaptureReview: Equatable, Identifiable {
        let id = UUID()
        var kind: CaptureKind
        /// The vision/lookup-produced items, each an editable estimate.
        var items: [LoggedFoodItem]
        /// What the model said it saw (photo/package), shown so the user can sanity-check recognition.
        var description: String?
        /// The on-device local path of the captured image, attached to the logged line for provenance.
        var photoLocalPath: String?
    }

    /// A scanned menu awaiting the user's multi-select picks.
    struct MenuReview: Equatable, Identifiable {
        let id = UUID()
        var candidates: [MenuItemCandidate]
    }

    private(set) var phase: Phase = .idle

    private let vision: any FoodVisionService
    private let imageStore: any FoodImageStore
    private let foodLog: FoodLogStore
    private let settings: FoodLogSettingsStore

    init(
        vision: any FoodVisionService,
        imageStore: any FoodImageStore,
        foodLog: FoodLogStore,
        settings: FoodLogSettingsStore
    ) {
        self.vision = vision
        self.imageStore = imageStore
        self.foodLog = foodLog
        self.settings = settings
    }

    private var bias: CalorieBias { settings.bias }
    private var micronutrients: MicronutrientToggles { settings.micronutrients }

    /// True while a sheet/scanner/review is presented; lets the bar disable re-entry mid-capture.
    var isBusy: Bool { phase != .idle }

    /// A food photo was captured/picked (`analyzeFood`). Persist on-device, then analyze.
    func handleFoodPhoto(_ imageJPEG: Data) {
        analyzeImage(imageJPEG, kind: .photo)
    }

    /// A package label was captured/picked (`analyzePackage`). Persist on-device, then analyze.
    func handlePackagePhoto(_ imageJPEG: Data) {
        analyzeImage(imageJPEG, kind: .package)
    }

    /// A menu was captured/picked (`scanMenu`). Extraction only: no on-device save (we keep dish names,
    /// not the menu photo), and no nutrition until the user picks.
    func handleMenuPhoto(_ imageJPEG: Data) {
        phase = .analyzing(.menu)
        Task { await runMenuScan(imageJPEG) }
    }

    func dismiss() {
        if case .reviewingEstimate(let review) = phase {
            discardSavedImage(review.photoLocalPath)
        }
        phase = .idle
    }

    /// Commit the (possibly hand-edited) estimate lines to today's journal. Each becomes a `.resolved`
    /// line carrying its estimate and the local photo path.
    func confirmEstimate(_ items: [LoggedFoodItem], from review: CaptureReview) {
        guard !items.isEmpty else { discardSavedImage(review.photoLocalPath); phase = .idle; return }
        foodLog.logCapturedLine(
            text: review.description ?? items.first?.name ?? "Logged from photo",
            items: items,
            photoLocalPath: review.photoLocalPath
        )
        discardSavedImage(review.photoLocalPath)
        phase = .idle
    }

    /// Log the user's selected menu dishes: each picked name runs through the core text pipeline as an
    /// optimistic line, like a typed entry. Nutrition is computed per pick, never for the whole menu.
    func confirmMenuPicks(_ picks: [MenuItemCandidate]) {
        for pick in picks {
            foodLog.logLine(pick.name, bias: bias, micronutrients: micronutrients)
        }
        phase = .idle
    }

    /// Persist the image on-device, then run the right vision call, then present editable estimates.
    private func analyzeImage(_ imageJPEG: Data, kind: CaptureKind) {
        phase = .analyzing(kind)
        Task {
            let path = try? await imageStore.save(imageJPEG: imageJPEG)
            do {
                let result: VisionFoodResult = switch kind {
                case .package:
                    try await vision.analyzePackage(
                        imageJPEG: imageJPEG, bias: bias, micronutrients: micronutrients
                    )
                default:
                    try await vision.analyzeFood(
                        imageJPEG: imageJPEG, bias: bias, micronutrients: micronutrients
                    )
                }
                guard !result.items.isEmpty else {
                    discardSavedImage(path)
                    phase = .error(FoodCaptureError.vision.userMessage)
                    return
                }
                phase = .reviewingEstimate(CaptureReview(
                    kind: kind,
                    items: result.items,
                    description: result.photoDescription,
                    photoLocalPath: path
                ))
            } catch let error as FoodCaptureError {
                discardSavedImage(path)
                phase = .error(error.userMessage)
            } catch {
                discardSavedImage(path)
                phase = .error(FoodCaptureError.vision.userMessage)
            }
        }
    }

    private func runMenuScan(_ imageJPEG: Data) async {
        do {
            let result = try await vision.scanMenu(imageJPEG: imageJPEG)
            guard result.isMenu else {
                let reason = result.reason.trimmingCharacters(in: .whitespacesAndNewlines)
                phase = .error(reason.isEmpty ? "That doesn't look like a menu. Try a clearer shot of the menu." : reason)
                return
            }
            guard !result.items.isEmpty else {
                phase = .error("No dishes were found on that menu. Try a clearer shot.")
                return
            }
            phase = .reviewingMenu(MenuReview(candidates: result.items))
        } catch let error as FoodCaptureError {
            phase = .error(error.userMessage)
        } catch {
            phase = .error(FoodCaptureError.vision.userMessage)
        }
    }

    /// Delete a saved capture image whose path is about to be dropped (failed vision call, dismissed
    /// review, or confirm). `logCapturedLine` records provenance as a note, not the path, so the file
    /// would otherwise be orphaned on disk as unreachable PHI. The `FoodImageStore` seam exposes only
    /// `save`, so cleanup reaches the concrete store's `delete` directly; once a photo column lands on
    /// `FoodJournalEntry`, deletion moves to `FoodLogStore.removeLine` and this stopgap goes away.
    /// No-ops for the preview/degraded stores, which never write a file.
    private func discardSavedImage(_ relativePath: String?) {
        guard let relativePath else { return }
        (imageStore as? LocalFoodImageStore)?.delete(relativePath: relativePath)
    }
}

#if DEBUG
extension FoodCaptureCoordinator {
    /// A preview-only coordinator wired to the synthetic stubs over the sample food log.
    @MainActor
    static var preview: FoodCaptureCoordinator {
        FoodCaptureCoordinator(
            vision: PreviewFoodVisionService(),
            imageStore: PreviewFoodImageStore(),
            foodLog: AppModel.sample.foodLog,
            settings: AppModel.sample.foodLogSettings
        )
    }
}
#endif
