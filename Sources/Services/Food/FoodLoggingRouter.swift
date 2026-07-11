import Foundation
import Observation

@MainActor
@Observable
final class FoodLoggingRouter: FoodLoggingService {
    private let savedFoods: SavedFoodsStore
    private let cache: NutritionCache
    private let menus: RestaurantMenuStore
    private let stated: any StatedNutritionResolver
    private let offClient: any OpenFoodFactsClient
    private let ai: any FoodNutritionAI

    init(
        savedFoods: SavedFoodsStore,
        cache: NutritionCache,
        menus: RestaurantMenuStore = RestaurantMenuStore(),
        stated: (any StatedNutritionResolver)? = nil,
        offClient: any OpenFoodFactsClient = HTTPOpenFoodFactsClient(),
        ai: any FoodNutritionAI
    ) {
        self.savedFoods = savedFoods
        self.cache = cache
        self.menus = menus
        self.stated = stated ?? StatedNutritionService(ai: ai)
        self.offClient = offClient
        self.ai = ai
    }

    /// Resolve a brand-new line: walk the full ladder (minus the edit branch) and return the first hit.
    /// Throws `.missingKey` (→ Settings, never retried) or `.transient` (the caller's queue retries,
    /// then applies the offline fallback).
    func resolveLine(_ request: FoodLineRequest) async throws -> FoodLineResult {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return FoodLineResult(items: []) }

        let water = WaterPhrasing.parse(text)
        if water.isWater { return FoodLineResult(items: [Self.waterItem(text: text, ml: water.milliliters)]) }

        if let shortcut = savedFoods.match(nickname: text) {
            savedFoods.bumpUse(id: shortcut.id)
            return FoodLineResult(items: shortcut.items)
        }

        if let cached = cache.record(for: text) {
            return FoodLineResult(items: Self.markCached(cached.baseItems))
        }

        if StatedNutrition.mightStateNutrition(text) {
            do {
                if let items = try await stated.resolve(line: text, micronutrients: request.micronutrients) {
                    cache.store(rawText: text, baseItems: items, sourceModel: "stated")
                    return FoodLineResult(items: items)
                }
            } catch AIProviderError.missingKey {
                throw FoodLoggingError.missingKey
            } catch {
                throw FoodLoggingError.transient
            }
        }

        if let menu = menus.match(line: text) {
            do {
                let items = try await ai.resolveFromMenu(
                    line: text, menu: menu, bias: request.bias, micronutrients: request.micronutrients
                )
                cache.store(rawText: text, baseItems: items, sourceModel: "menu:\(menu.brand)")
                return FoodLineResult(items: items)
            } catch AIProviderError.missingKey {
                throw FoodLoggingError.missingKey
            } catch {
            }
        }

        if !Self.looksComposedDish(text), let match = try? await offClient.searchProduct(query: text) {
            cache.store(rawText: text, baseItems: [match.item], sourceModel: "openfoodfacts")
            return FoodLineResult(items: [match.item])
        }

        do {
            let items = try await ai.resolveNovel(
                line: text, bias: request.bias, micronutrients: request.micronutrients
            )
            cache.store(rawText: text, baseItems: items, sourceModel: "perplexity/sonar")
            return FoodLineResult(items: items)
        } catch AIProviderError.missingKey {
            throw FoodLoggingError.missingKey
        } catch {
            throw FoodLoggingError.transient
        }
    }

    /// Resolve an edit to an existing line. A portion-only change takes the cheap Gemini rescale (no web
    /// search); substantive new content falls through to a fresh novel resolve.
    func resolveEdit(_ request: FoodEditRequest) async throws -> FoodLineResult {
        let newText = request.newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newText.isEmpty else { return FoodLineResult(items: []) }

        let water = WaterPhrasing.parse(newText)
        if water.isWater { return FoodLineResult(items: [Self.waterItem(text: newText, ml: water.milliliters)]) }

        if let shortcut = savedFoods.match(nickname: newText) {
            savedFoods.bumpUse(id: shortcut.id)
            return FoodLineResult(items: shortcut.items)
        }
        if let cached = cache.record(for: newText) {
            return FoodLineResult(items: Self.markCached(cached.baseItems))
        }

        if StatedNutrition.mightStateNutrition(newText) {
            do {
                if let items = try await stated.resolve(line: newText, micronutrients: request.micronutrients) {
                    return FoodLineResult(items: items)
                }
            } catch AIProviderError.missingKey {
                throw FoodLoggingError.missingKey
            } catch {
                throw FoodLoggingError.transient
            }
        }

        if Self.looksPortionOnly(old: request.oldText, new: newText), !request.existingItems.isEmpty {
            do {
                let items = try await ai.rescalePortion(
                    oldLine: request.oldText, newLine: newText, base: request.existingItems,
                    bias: request.bias, micronutrients: request.micronutrients
                )
                return FoodLineResult(items: items)
            } catch AIProviderError.missingKey {
                throw FoodLoggingError.missingKey
            } catch {
                throw FoodLoggingError.transient
            }
        }

        return try await resolveLine(FoodLineRequest(
            text: newText, bias: request.bias, micronutrients: request.micronutrients
        ))
    }

    /// A composed/restaurant-style dish: multiple comma-separated components, or a long multi-word
    /// description, not a single packaged product. Open Food Facts carries only packaged products, so
    /// for these it returns a misleading fuzzy match; they skip OFF and go straight to the Sonar estimate.
    static func looksComposedDish(_ text: String) -> Bool {
        if text.contains(",") { return true }
        return text.split(whereSeparator: \.isWhitespace).count > 5
    }

    /// Stamp reused cache-hit items as `.cached` (keeping their values/assumptions/citations) so the row
    /// shows they came from a saved entry, not a fresh estimate.
    private static func markCached(_ items: [LoggedFoodItem]) -> [LoggedFoodItem] {
        items.map { item in
            var copy = item
            copy.provenance = .cached
            return copy
        }
    }

    /// Heuristic for a portion-only edit: the new text is the old text plus/minus a quantity phrase
    /// ("half", "a couple bites of", "2x", a number). Conservative: when unsure, treat it as
    /// substantive, which is safe: it just costs a normal resolve, never a wrong number. The model still
    /// does the real rescale; this only picks the cheap lane vs a fresh resolve.
    static func looksPortionOnly(old: String, new: String) -> Bool {
        let o = old.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let n = new.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !o.isEmpty, !n.isEmpty, o != n else { return false }
        return core(o) == core(n)
    }

    /// Reduce a food line to its identifying words: drop quantity/portion words, articles, and digits,
    /// matching whole words so a short token like "of" never strips letters inside another word (the
    /// "of" in "coffee"). Conservative: an unmatched word stays, so adding a real ingredient keeps a
    /// different core and falls through to a fresh resolve.
    private static func core(_ s: String) -> String {
        s.split(whereSeparator: \.isWhitespace)
            .map { token in String(token.filter { !$0.isNumber && $0 != "." && $0 != "/" }) }
            .filter { !$0.isEmpty && !portionWords.contains($0) }
            .joined(separator: " ")
    }

    /// Whole words that signal a portion/quantity change (or are filler), not a different food. Whole-word
    /// matching is what makes short words like "a"/"of" safe to include; substring stripping was not.
    private static let portionWords: Set<String> = [
        "half", "quarter", "some", "a", "an", "the", "little", "double", "two", "three", "x",
        "small", "large", "extra", "more", "less", "portion", "serving", "servings",
        "of", "couple", "few", "bite", "bites",
    ]

    /// A zero-calorie water item; defensive duplicate of the UX water path so a water line never reaches
    /// an AI lane through this router.
    private static func waterItem(text: String, ml: Double?) -> LoggedFoodItem {
        LoggedFoodItem(
            name: text, calories: 0,
            assumptions: "Logged as water, excluded from calories.",
            confidenceScore: 100, isWaterEntry: true, waterMilliliters: ml
        )
    }
}
