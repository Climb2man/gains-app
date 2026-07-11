#if DEBUG
import Foundation
import UIKit

/// A no-key provider for previews: returns `nil` (the "no key yet" state) so a preview never attempts
/// a real OpenRouter call. Never holds a real key.
struct PreviewKeyProvider: OpenRouterKeyProviding {
    func openRouterKey() async throws -> String? { nil }
}

/// A canned `FoodVisionService` for previews: returns fixed synthetic results immediately. No image
/// is read, nothing egresses; the numbers are obvious placeholders.
struct PreviewFoodVisionService: FoodVisionService {
    func analyzeFood(
        imageJPEG: Data, bias: CalorieBias, micronutrients: MicronutrientToggles
    ) async throws -> VisionFoodResult {
        VisionFoodResult(
            items: [
                LoggedFoodItem(name: "Grilled chicken", calories: 280, proteinG: 42, carbsG: 0, fatG: 12,
                               assumptions: "Synthetic preview estimate.", confidenceScore: 70),
                LoggedFoodItem(name: "White rice", calories: 200, proteinG: 4, carbsG: 44, fatG: 0,
                               assumptions: "Synthetic preview estimate.", confidenceScore: 70),
            ],
            photoDescription: "A plate of grilled chicken with rice (synthetic preview)."
        )
    }

    func scanMenu(imageJPEG: Data) async throws -> MenuScanResult {
        MenuScanResult(
            isMenu: true,
            items: [
                MenuItemCandidate(name: "Carne Asada Taco", section: "Tacos"),
                MenuItemCandidate(name: "Chicken Burrito", section: "Burritos"),
                MenuItemCandidate(name: "Chips and Guacamole", section: "Sides"),
            ]
        )
    }

    func analyzePackage(
        imageJPEG: Data, bias: CalorieBias, micronutrients: MicronutrientToggles
    ) async throws -> VisionFoodResult {
        VisionFoodResult(
            items: [
                LoggedFoodItem(name: "Protein bar", calories: 210, proteinG: 20, carbsG: 22, fatG: 7,
                               assumptions: "Synthetic preview estimate. Per serving: 1 bar (60 g).",
                               confidenceScore: 80),
            ],
            photoDescription: nil
        )
    }
}

/// An in-memory `FoodImageStore` for previews: "saves" nothing and returns a fake path, so no PHI
/// touches the disk.
struct PreviewFoodImageStore: FoodImageStore {
    func save(imageJPEG: Data) async throws -> String { "preview-\(UUID().uuidString).jpg" }
}
#endif
