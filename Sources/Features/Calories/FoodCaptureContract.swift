import Foundation
import Observation

/// One item the vision model returned for a food photo or package label (`analyzeFood` /
/// `analyzePackage`). Reuses `LoggedFoodItem` so it flows through the same review and logging path as a
/// typed line; every number is an editable estimate the user confirms.
struct VisionFoodResult: Sendable {
    /// The resolved item(s). A photo of a plate may split into several (rice, chicken, veg).
    var items: [LoggedFoodItem]
    /// The model's short description of what it saw (`photo_food_description`), shown above the editable
    /// lines so the user can sanity-check recognition before confirming.
    var photoDescription: String?

    init(items: [LoggedFoodItem], photoDescription: String? = nil) {
        self.items = items
        self.photoDescription = photoDescription
    }
}

/// One candidate dish the menu scanner extracted (`scanMenu`): a name plus the section it sat under
/// (e.g. "Tacos", "Sides"), so the review sheet can group picks the way the menu was laid out.
/// Extraction only; nutrition is computed per selected item through the core text pipeline, so only the
/// user's picks are analyzed, not the whole menu.
struct MenuItemCandidate: Identifiable, Hashable, Sendable {
    let id: String
    /// The dish name as printed on the menu; becomes the food text routed through the core text pipeline.
    var name: String
    /// The menu section heading this dish sat under, or nil when the menu had no sections.
    var section: String?

    init(id: String = UUID().uuidString, name: String, section: String? = nil) {
        self.id = id
        self.name = name
        self.section = section
    }
}

/// The `scanMenu` result: `{ isMenu, reason, items }`. When `isMenu` is false the UX shows `reason` and
/// offers no picks; when true it lists `items` grouped by section for multi-select.
struct MenuScanResult: Sendable {
    /// Whether the image was recognized as a menu.
    var isMenu: Bool
    /// Why it was not a menu, shown when `isMenu` is false. Empty when it is a menu.
    var reason: String
    /// The extracted dish candidates (empty when `isMenu` is false).
    var items: [MenuItemCandidate]

    init(isMenu: Bool, reason: String = "", items: [MenuItemCandidate] = []) {
        self.isMenu = isMenu
        self.reason = reason
        self.items = items
    }
}

/// The vision surface for food-photo, menu-scan, and package-label analysis. Implemented over the
/// `AIProvider` vision path (a base64 image part on the user's key); the UX depends only on this
/// protocol. Each call takes already-encoded JPEG `Data`, persisted on-device first, then a copy is
/// handed here for the single egress.
///
/// Throws `FoodCaptureError` (`.missingKey` routes to Settings); never fabricates a value.
protocol FoodVisionService: Sendable {
    /// Photo of food → `analyzeFood`: returns editable estimate items plus a description of the plate.
    /// `bias`/`micronutrients` flow through like a typed line so the lean stays consistent.
    func analyzeFood(
        imageJPEG: Data, bias: CalorieBias, micronutrients: MicronutrientToggles
    ) async throws -> VisionFoodResult

    /// Menu scan → `scanMenu`: extraction only, no nutrition. Returns `{ isMenu, reason, items }`.
    func scanMenu(imageJPEG: Data) async throws -> MenuScanResult

    /// Package label → `analyzePackage`: returns editable estimate items (macros + serving) for the
    /// scanned nutrition label.
    func analyzePackage(
        imageJPEG: Data, bias: CalorieBias, micronutrients: MicronutrientToggles
    ) async throws -> VisionFoodResult
}

/// The encrypted on-device image store, referenced by local path. The persistence layer provides the
/// concrete AES-256-GCM file store (key in the Keychain). The UX saves the captured JPEG here first,
/// gets a stable local path back, attaches it to the logged item, and hands a copy of the bytes to the
/// single vision egress. The image is never uploaded.
protocol FoodImageStore: Sendable {
    /// Persist captured JPEG bytes on-device and return a stable local path to reference later.
    /// Throws `FoodCaptureError.imageStore` on a write failure; never silently drops the photo.
    func save(imageJPEG: Data) async throws -> String
}

/// Fallback `FoodImageStore` used only when the encrypted local store can't be created, so app launch
/// never fails over photo persistence. It saves nothing and reports the failure, so the capture flow
/// logs the estimate without a photo path rather than crashing or falsely claiming the photo was stored.
struct NoopFoodImageStore: FoodImageStore {
    func save(imageJPEG: Data) async throws -> String { throw FoodCaptureError.imageStore }
}

/// Failures the capture flows surface. `.missingKey` routes to Settings (mirrors `FoodLoggingError`);
/// every other case is a friendly, non-credential message shown inline. No case ever carries the API
/// key, image bytes, or any request detail.
enum FoodCaptureError: Error, Equatable, Sendable {
    /// No OpenRouter key stored yet; prompt to add one in Settings.
    case missingKey
    /// The vision/network call failed (no/garbled response). Shown as "couldn't read that, try again".
    case vision
    /// The on-device image store couldn't persist the photo.
    case imageStore
    /// The camera/photo library wasn't available or permission was denied.
    case captureUnavailable

    /// A friendly, non-credential message for inline display.
    var userMessage: String {
        switch self {
        case .missingKey:
            "Add your OpenRouter API key in Settings to read photos and menus."
        case .vision:
            "Couldn't read that image. Try a clearer, well-lit shot, or type the food instead."
        case .imageStore:
            "Couldn't save that photo on your device. Try again."
        case .captureUnavailable:
            "The camera or photo library isn't available. Check permissions in Settings."
        }
    }
}
