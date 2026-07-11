import Foundation

/// One official menu component (a build-your-own ingredient or a fixed item), macros as published.
struct RestaurantMenuItem: Codable, Equatable, Sendable {
    var name: String
    var portion: String
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double?
    var sugarG: Double?
    var sodiumMg: Double?

    enum CodingKeys: String, CodingKey {
        case name, portion, calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
        case sugarG = "sugar_g"
        case sodiumMg = "sodium_mg"
    }
}

/// One brand's bundled menu + the words that gate it in.
struct RestaurantMenu: Codable, Equatable, Sendable {
    var brand: String
    /// Lowercase words that, when present in a food line, select this menu (e.g. ["chipotle"]).
    var aliases: [String]
    /// Provenance for the numbers (shown/logged so every value traces to a named source).
    var source: String
    var items: [RestaurantMenuItem]

    /// The items as a compact JSON string for grounding an AI call. Emits the same key names the model
    /// must output (`protein`/`carbs`/`fat`, not the `_g` keys) so it copies the official numbers
    /// through instead of zeroing macros it can't map.
    func itemsContextJSON() -> String {
        let context = items.map(GroundingItem.init(from:))
        return (try? String(data: JSONEncoder().encode(context), encoding: .utf8)) ?? "[]"
    }

    /// Output-shaped view of a menu item used only to ground the prompt (keys match the response schema).
    private struct GroundingItem: Encodable {
        let name: String
        let portion: String
        let calories: Double
        let protein: Double
        let carbs: Double
        let fat: Double
        let fiber: Double?
        let sugar: Double?
        let sodium: Double?

        init(from item: RestaurantMenuItem) {
            name = item.name
            portion = item.portion
            calories = item.calories
            protein = item.proteinG
            carbs = item.carbsG
            fat = item.fatG
            fiber = item.fiberG
            sugar = item.sugarG
            sodium = item.sodiumMg
        }
    }
}
