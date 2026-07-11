import Foundation

/// `FoodVisionService` over the app's `AIProvider`. Prompt-build + decode + reconcile; the transport
/// (OpenRouter, BYOK, key handling, inline-image encoding) lives in the injected provider's
/// `completeVisionJSON`. `mimeType` defaults to JPEG, the bytes the UX/image-store produce.
struct OpenRouterFoodVisionService: FoodVisionService {
    private let provider: any AIProvider
    private let mimeType: String

    init(provider: any AIProvider, mimeType: String = "image/jpeg") {
        self.provider = provider
        self.mimeType = mimeType
    }

    func analyzeFood(
        imageJPEG: Data, bias: CalorieBias, micronutrients: MicronutrientToggles
    ) async throws -> VisionFoodResult {
        let raw = try await vision(
            system: Self.photoSystemPrompt(bias: bias, micronutrients: micronutrients),
            prompt: "Identify everything edible in this photo and estimate its nutrition.",
            imageJPEG: imageJPEG
        )
        let result: PhotoFoodResult = try Self.decode(raw)
        guard !result.items.isEmpty else { throw FoodCaptureError.vision }
        let items = result.items.map { FoodAINutritionService.reconciled($0.asLoggedItem()) }
        let caption = result.photoFoodDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        return VisionFoodResult(
            items: items,
            photoDescription: (caption?.isEmpty == false) ? caption : nil
        )
    }

    func scanMenu(imageJPEG: Data) async throws -> MenuScanResult {
        let raw = try await vision(
            system: Self.menuSystemPrompt,
            prompt: "Determine whether this image is a food menu and, if so, extract its items by section.",
            imageJPEG: imageJPEG,
            maxTokens: 1500
        )
        let wire: MenuScanWire = try Self.decode(raw)
        let candidates = wire.items.map {
            MenuItemCandidate(
                name: $0.name,
                section: $0.section?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? $0.section : nil
            )
        }
        if wire.isMenu {
            guard !candidates.isEmpty else { throw FoodCaptureError.vision }
        }
        return MenuScanResult(
            isMenu: wire.isMenu,
            reason: wire.reason ?? "",
            items: wire.isMenu ? candidates : []
        )
    }

    func analyzePackage(
        imageJPEG: Data, bias: CalorieBias, micronutrients: MicronutrientToggles
    ) async throws -> VisionFoodResult {
        let raw = try await vision(
            system: Self.packageSystemPrompt(bias: bias, micronutrients: micronutrients),
            prompt: "Read this nutrition label and return the per-serving nutrition and serving size.",
            imageJPEG: imageJPEG,
            maxTokens: 600
        )
        let result: PackageLabelResult = try Self.decode(raw)
        var item = FoodAINutritionService.reconciled(result.item.asLoggedItem())
        if let serving = result.servingDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           !serving.isEmpty {
            let note = "Per serving: \(serving)."
            item.assumptions = item.assumptions.map { "\($0) \(note)" } ?? note
        }
        return VisionFoodResult(items: [item], photoDescription: nil)
    }

    /// One vision call: base64-encode the JPEG locally and hand it to the provider. Maps provider errors
    /// onto the `FoodCaptureError` the UX expects (missing key → Settings; anything else → a "couldn't
    /// read that" vision error). The key and image never appear in a thrown error.
    private func vision(
        system: String, prompt: String, imageJPEG: Data, maxTokens: Int = 900
    ) async throws -> String {
        do {
            return try await provider.completeVisionJSON(
                system: system,
                prompt: prompt,
                imageBase64: imageJPEG.base64EncodedString(),
                mimeType: mimeType,
                maxTokens: maxTokens
            )
        } catch AIProviderError.missingKey {
            throw FoodCaptureError.missingKey
        } catch {
            throw FoodCaptureError.vision
        }
    }

    /// Decode a strict-JSON vision response into `T`, tolerating a ```json fence. A non-decodable body
    /// → `.vision`, never a fabricated value. Reuses `FoodAINutritionService`'s fence stripper.
    private static func decode<T: Decodable>(_ raw: String) throws -> T {
        let cleaned = FoodAINutritionService.stripFence(raw)
        guard let data = cleaned.data(using: .utf8) else { throw FoodCaptureError.vision }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw FoodCaptureError.vision
        }
    }

    /// Photo-of-food prompt: return items[] (the shared per-item shape) plus a `photo_food_description`
    /// caption. States the general-wellness framing.
    static func photoSystemPrompt(bias: CalorieBias, micronutrients: MicronutrientToggles) -> String {
        """
        You are a nutrition estimator looking at a PHOTO of food, producing a GENERAL-WELLNESS \
        ESTIMATE, never medical or dietary advice, never a diagnosis. Identify each distinct edible \
        item visible and estimate its nutrition from the typical portions you can see. Return STRICT \
        JSON of the form { "photo_food_description": "<short caption of the whole plate>", "items": [ \
        { name (string), calories (number), protein (number, g), carbs (number, g), fat (number, g)\
        \(FoodAINutritionService.micronutrientClause(micronutrients)), citations (array of strings, \
        may be empty for a visual estimate), thoughtProcess (short string: what you saw and assumed), \
        confidenceScore (number 0-100) } ] }. Keep each item internally consistent: calories should be \
        approximately 4*protein + 4*carbs + 9*fat. Split distinct foods into separate items. Calorie \
        bias = \(bias.promptInstruction). If nothing edible is visible, return an empty items array. \
        Output JSON only, no prose, no code fence.
        """
    }

    /// Menu-scan prompt: extraction only, no nutrition, so the whole menu is never priced; only the
    /// user's later picks are.
    static let menuSystemPrompt =
        """
        You are reading an image to decide whether it is a FOOD MENU and, if so, to extract its items. \
        Return STRICT JSON of EXACTLY this shape: { "isMenu": <true|false>, "reason": "<short \
        explanation, empty string when isMenu is true>", "items": [ { "name": "<dish name as \
        printed>", "section": "<the menu section/heading it sits under, or empty string>" } ] }. Do \
        NOT estimate any nutrition, prices, calories, or macros: extract names and sections only. If \
        the image is not a food menu, set isMenu to false, give a brief reason, and return an empty \
        items array. Output JSON only, no prose, no code fence.
        """

    /// Package-label prompt: read the Nutrition Facts panel into one per-serving item plus a serving
    /// description. States the general-wellness framing.
    static func packageSystemPrompt(bias: CalorieBias, micronutrients: MicronutrientToggles) -> String {
        """
        You are reading a packaged food's NUTRITION LABEL, producing a GENERAL-WELLNESS ESTIMATE, \
        never advice or a diagnosis. Read the Nutrition Facts panel and return the values FOR ONE \
        STATED SERVING. Return STRICT JSON of the form { "serving_description": "<the serving size \
        the label states, e.g. '1 bar (40 g)'>", "item": { name (string: the product if legible, \
        else 'Packaged food'), calories (number), protein (number, g), carbs (number, g), fat \
        (number, g)\(FoodAINutritionService.micronutrientClause(micronutrients)), citations (array, \
        may be empty), thoughtProcess (short string), confidenceScore (number 0-100) } }. Use the \
        numbers printed on the label; keep them internally consistent (calories ≈ 4*protein + 4*carbs \
        + 9*fat). Calorie bias = \(bias.promptInstruction). Output JSON only, no prose, no code fence.
        """
    }
}

/// The photo-of-food result: `{ photo_food_description, items: [ {…} ] }`. Reuses the shared
/// `NutritionItemWire` so macro mapping/reconciliation matches the text lane.
private struct PhotoFoodResult: Decodable {
    var photoFoodDescription: String?
    var items: [NutritionItemWire]

    enum CodingKeys: String, CodingKey {
        case photoFoodDescription = "photo_food_description"
        case items
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        photoFoodDescription = try c.decodeIfPresent(String.self, forKey: .photoFoodDescription)
        items = (try? c.decode([NutritionItemWire].self, forKey: .items)) ?? []
    }
}

/// The menu-scan wire shape: `{ isMenu, reason, items: [{ name, section }] }`. Decoded here then
/// mapped to the shared `MenuScanResult` / `MenuItemCandidate` (FoodCaptureContract.swift). Absent
/// `reason`/`section` decode to ""/nil rather than failing.
private struct MenuScanWire: Decodable {
    var isMenu: Bool
    var reason: String?
    var items: [Item]

    struct Item: Decodable {
        var name: String
        var section: String?
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isMenu = try c.decode(Bool.self, forKey: .isMenu)
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        items = (try? c.decode([Item].self, forKey: .items)) ?? []
    }

    enum CodingKeys: String, CodingKey { case isMenu, reason, items }
}

/// The package-label result: `{ serving_description, item: {…} }`.
private struct PackageLabelResult: Decodable {
    var servingDescription: String?
    var item: NutritionItemWire

    enum CodingKeys: String, CodingKey {
        case servingDescription = "serving_description"
        case item
    }
}
