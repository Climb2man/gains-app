import Foundation

/// The food-nutrition AI surface. A protocol so the router depends on intent, not wire shape
/// (thin seams) and tests can stub it.
protocol FoodNutritionAI: Sendable {
    /// Resolve a novel food line via web-grounded search (Sonar). Returns biased items with citations
    /// and the enabled micronutrients. Throws `AIProviderError` (incl. `.missingKey`); never fabricates.
    func resolveNovel(
        line: String, bias: CalorieBias, micronutrients: MicronutrientToggles
    ) async throws -> [LoggedFoodItem]

    /// Rescale existing nutrition for a portion/edit (cheap Gemini, no web search). Takes the prior
    /// line, the new line, and the base items; returns the rescaled items. Throws on failure.
    func rescalePortion(
        oldLine: String?, newLine: String, base: [LoggedFoodItem],
        bias: CalorieBias, micronutrients: MicronutrientToggles
    ) async throws -> [LoggedFoodItem]

    /// Resolve a line naming a known brand, grounded in that brand's bundled official menu. Cheap lane,
    /// no web search: the model maps the order to the supplied official items and returns them with the
    /// exact published numbers (off-menu add-ons are estimated and biased). Throws on failure; never
    /// fabricates.
    func resolveFromMenu(
        line: String, menu: RestaurantMenu, bias: CalorieBias, micronutrients: MicronutrientToggles
    ) async throws -> [LoggedFoodItem]

    /// Extract only the literal nutrition the user stated in a line: per-serving calories/macros, a
    /// serving size, a total amount, a servings count. Does no arithmetic (the caller does the math).
    /// Cheap lane, no web search. Throws on failure; never fabricates.
    func extractStated(line: String) async throws -> StatedNutritionWire
}

/// `FoodNutritionAI` over the app's `AIProvider`. Pure prompt-build + decode + reconcile; the
/// transport (OpenRouter, BYOK, key handling) is entirely inside the injected provider.
struct FoodAINutritionService: FoodNutritionAI {
    private let provider: any AIProvider

    init(provider: any AIProvider) {
        self.provider = provider
    }

    func resolveNovel(
        line: String, bias: CalorieBias, micronutrients: MicronutrientToggles
    ) async throws -> [LoggedFoodItem] {
        let messages = [
            ChatMessage(.system, Self.novelSystemPrompt(bias: bias, micronutrients: micronutrients)),
            ChatMessage(.user, "Estimate nutrition for this food line: \(line)"),
        ]
        let raw = try await provider.completeJSON(messages: messages, lane: .novel, maxTokens: 1200)
        let result: SonarFoodResult = try Self.decode(raw)
        guard !result.items.isEmpty else { throw AIProviderError.decoding }
        return result.items.map { Self.reconciled($0.asLoggedItem()) }
    }

    func rescalePortion(
        oldLine: String?, newLine: String, base: [LoggedFoodItem],
        bias: CalorieBias, micronutrients: MicronutrientToggles
    ) async throws -> [LoggedFoodItem] {
        let baseWire = base.map(NutritionItemWire.init(from:))
        let baseJSON = (try? String(data: JSONEncoder().encode(baseWire), encoding: .utf8)) ?? "[]"
        var userLines = ["Existing nutrition (JSON items): \(baseJSON)"]
        if let oldLine, !oldLine.isEmpty { userLines.append("The line previously read: \(oldLine)") }
        userLines.append("The line now reads: \(newLine)")
        userLines.append(
            "Rescale the existing nutrition to match the NEW line's portion/quantity ONLY. "
            + "Do not research new foods. Adjust the numbers proportionally."
        )

        let messages = [
            ChatMessage(.system, Self.rescaleSystemPrompt(bias: bias, micronutrients: micronutrients)),
            ChatMessage(.user, userLines.joined(separator: "\n")),
        ]
        let raw = try await provider.completeJSON(messages: messages, lane: .cheap, maxTokens: 900)
        let result: GeminiEditResult = try Self.decode(raw)
        let items = result.modifiedNutrition.items
        guard !items.isEmpty else { throw AIProviderError.decoding }
        let baseCitations = base.flatMap(\.citations)
        return items.map { wire in
            var item = wire.asLoggedItem()
            if item.citations.isEmpty { item.citations = baseCitations }
            return Self.reconciled(item)
        }
    }

    func resolveFromMenu(
        line: String, menu: RestaurantMenu, bias: CalorieBias, micronutrients: MicronutrientToggles
    ) async throws -> [LoggedFoodItem] {
        let messages = [
            ChatMessage(.system, Self.menuSystemPrompt(menu: menu, bias: bias, micronutrients: micronutrients)),
            ChatMessage(.user, "The user logged this order at \(menu.brand): \(line)"),
        ]
        let raw = try await provider.completeJSON(messages: messages, lane: .cheap, maxTokens: 1000)
        let result: SonarFoodResult = try Self.decode(raw)
        guard !result.items.isEmpty else { throw AIProviderError.decoding }
        return result.items.map { Self.reconciled($0.asLoggedItem()) }
    }

    func extractStated(line: String) async throws -> StatedNutritionWire {
        let messages = [
            ChatMessage(.system, Self.statedExtractPrompt),
            ChatMessage(.user, "Extract stated nutrition from this food line: \(line)"),
        ]
        let raw = try await provider.completeJSON(messages: messages, lane: .cheap, maxTokens: 400)
        return try Self.decode(raw)
    }

    /// Extract-only prompt: copy the user's numbers verbatim, do no arithmetic, leave unstated fields
    /// null. The Swift caller (`StatedNutritionService`) does all scaling and unit conversion.
    static let statedExtractPrompt = """
        You read a free-text food line and EXTRACT the nutrition the user explicitly STATED. You do NO \
        arithmetic: never multiply, never sum, never convert units. Return STRICT JSON: \
        { "statesNutrition": <bool>, "name": <string, the food with nutrition/serving phrases removed>, \
        "basis": "per_serving" | "total" (are the `per` numbers per ONE serving, or for the whole amount?), \
        "per": { "calories": <number|null>, "protein_g": <number|null>, "carbs_g": <number|null>, \
        "fat_g": <number|null>, "sugar_g": <number|null>, "fiber_g": <number|null>, "sodium_mg": <number|null> }, \
        "serving": { "amount": <number|null>, "unit": "g"|"oz"|"lb"|"ml"|null }, \
        "total": { "amount": <number|null>, "unit": "g"|"oz"|"lb"|"ml"|null }, \
        "servingsCount": <number|null> }. \
        Set statesNutrition=true ONLY if the line states real calories AND/OR macro grams; otherwise set \
        it false and `per` null. Copy each number EXACTLY as written. Example: for "170 cal & 24g protein \
        per 4 oz serving, I had 1.5 lb" return statesNutrition=true, per.calories=170, per.protein_g=24, \
        basis="per_serving", serving={amount:4,unit:"oz"}, total={amount:1.5,unit:"lb"}. Do the math \
        NOWHERE. Output JSON only, no prose, no code fence.
        """

    /// Decode a strict-JSON model response into `T`. A non-decodable body → `.decoding` (never a
    /// fabricated value). Tolerates the model wrapping JSON in a ```json fence by stripping it.
    private static func decode<T: Decodable>(_ raw: String) throws -> T {
        let cleaned = stripFence(raw)
        guard let data = cleaned.data(using: .utf8) else { throw AIProviderError.decoding }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw AIProviderError.decoding
        }
    }

    /// Strip a leading/trailing markdown code fence if the model added one. `static` + internal so the
    /// vision lane (`FoodVisionService`) reuses the same fence handling.
    static func stripFence(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("```") else { return s }
        if let firstNewline = s.firstIndex(of: "\n") {
            s = String(s[s.index(after: firstNewline)...])
        }
        if let fence = s.range(of: "```", options: .backwards) {
            s = String(s[..<fence.lowerBound])
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let kcalPerProteinG = 4.0
    private static let kcalPerCarbG = 4.0
    private static let kcalPerFatG = 9.0
    /// How far calories may drift from `4P+4C+9F` before we reconcile (10%). Small rounding is fine; a
    /// real mismatch (and >25 kcal absolute) is a safety bug.
    private static let tolerance = 0.10

    /// Reconcile one item so `calories ≈ 4·P + 4·C + 9·F`. When the macros imply a materially different
    /// calorie figure, trust the macros and set calories from them. Never invent macros to fit a
    /// number. Within tolerance the model's numbers are left alone. Water items (calories 0) are never
    /// touched.
    static func reconciled(_ item: LoggedFoodItem) -> LoggedFoodItem {
        guard !item.isWaterEntry else { return item }
        let macroCalories =
            item.proteinG * kcalPerProteinG + item.carbsG * kcalPerCarbG + item.fatG * kcalPerFatG
        guard macroCalories > 0 || item.calories > 0 else { return item }
        let reference = max(macroCalories, 1)
        let drift = abs(item.calories - macroCalories) / reference
        guard drift > tolerance, abs(item.calories - macroCalories) > 25 else { return item }
        var fixed = item
        fixed.calories = macroCalories.rounded()
        return fixed
    }

    /// Novel/Sonar system prompt: fills the bias slot, requests the enabled micronutrients, and states
    /// the general-wellness framing.
    static func novelSystemPrompt(bias: CalorieBias, micronutrients: MicronutrientToggles) -> String {
        """
        You are a nutrition estimator producing a GENERAL-WELLNESS ESTIMATE, never medical or dietary \
        advice, never a diagnosis. Given a free-text food line, return STRICT JSON with an `items` \
        array; each item has: name (string), calories (number), protein (number, g), carbs (number, g), \
        fat (number, g)\(Self.micronutrientClause(micronutrients)), a `citations` array of real source \
        URLs you used, a CONCISE one-sentence first-person `thoughtProcess` (the source you used plus any \
        key assumption or portion choice; if the bias is not balanced, state the buffer you applied, \
        e.g. "I added a 20% buffer for aggressive overestimation"), and a `confidenceScore` 0–100 (how \
        well published/verified reference values back the estimate). PORTION RULES: respect any \
        explicitly stated weight or measure EXACTLY (1 oz = 28 g; treat meat and grain weights as COOKED \
        unless the user says raw). When NO portion is given, size each component to a FULL, GENEROUS \
        REAL-WORLD serving, and for anything that reads like a RESTAURANT or composed plated dish, use \
        RESTAURANT portions, which are large: a plated half chicken (bone-in, skin on) is ~600–700 kcal, \
        a restaurant starch side (polenta, mashed potato, rice, pasta) is ~1–1.5 cups, a steak entrée is \
        8–12 oz, a sandwich/burrito is a full hand-sized portion. If genuinely uncertain between sizes, \
        choose the LARGER. Under-counting calories is the riskier error for the user. Keep each item \
        internally consistent: calories should be approximately \
        4*protein + 4*carbs + 9*fat. Calorie bias = \(bias.promptInstruction). Prefer brand or \
        restaurant-published data, then USDA, then reputable nutrition databases. Split a multi-food \
        line into multiple items. Output JSON only, no prose, no code fence.
        """
    }

    /// Edit/portion (Gemini) system prompt: rescale only, no web search, returns the `modifiedNutrition`
    /// shape.
    static func rescaleSystemPrompt(bias: CalorieBias, micronutrients: MicronutrientToggles) -> String {
        """
        You rescale an existing nutrition estimate for a portion or wording change, a \
        GENERAL-WELLNESS ESTIMATE, never advice or a diagnosis. You are given existing nutrition and a \
        new food line. Adjust the numbers to the new portion/quantity ONLY; do NOT research new foods. \
        Return STRICT JSON of the form { "modifiedNutrition": { "items": [ { name, calories, protein, \
        carbs, fat\(Self.micronutrientClause(micronutrients)), citations, thoughtProcess, \
        confidenceScore } ] } } where protein/carbs/fat are grams. Keep each item consistent: \
        calories ≈ 4*protein + 4*carbs + 9*fat. Calorie bias = \(bias.promptInstruction). Output JSON \
        only, no prose, no code fence.
        """
    }

    /// Brand-menu system prompt: ground the model in the bundled official items so listed components use
    /// the exact published numbers (no buffer); only off-menu add-ons get the bias.
    static func menuSystemPrompt(
        menu: RestaurantMenu, bias: CalorieBias, micronutrients: MicronutrientToggles
    ) -> String {
        """
        You are matching a customer's order to a restaurant's OFFICIAL published nutrition facts, a \
        GENERAL-WELLNESS log, never advice or a diagnosis. Here are \(menu.brand)'s official items, each \
        per its listed portion, as JSON:
        \(menu.itemsContextJSON())
        Return STRICT JSON { "items": [ ... ] }; each item has name (string), calories (number), protein \
        (number, g), carbs (number, g), fat (number, g)\(Self.micronutrientClause(micronutrients)), a \
        `citations` array (use ["\(menu.source)"] for items taken from the official list), a first-person \
        `thoughtProcess`, and a `confidenceScore` 0–100. RULES: (1) For anything on the official list use \
        its EXACT published numbers. Do NOT apply any buffer, they are already exact. Scale by the \
        quantity ordered ("double chicken" = 2× chicken, "extra cheese" = 2× cheese, "no rice" = omit). A \
        burrito or bowl normally includes the tortilla (burrito only), rice, beans, the chosen meat, \
        salsa, and cheese unless the order says otherwise. Include only the components the order implies. \
        (2) For an add-on NOT on the list, estimate it and apply calorie bias = \(bias.promptInstruction). \
        (3) Return one item per component so the user sees the breakdown. Keep each item consistent: \
        calories ≈ 4*protein + 4*carbs + 9*fat. Output JSON only, no prose, no code fence.
        """
    }

    /// Clause listing the enabled micronutrients to include (empty when none are tracked). `static` +
    /// internal so the vision lane (`FoodVisionService`) requests the same micros.
    static func micronutrientClause(_ toggles: MicronutrientToggles) -> String {
        var parts: [String] = []
        if toggles.sugar { parts.append("sugar (number, g)") }
        if toggles.fiber { parts.append("fiber (number, g)") }
        if toggles.sodium { parts.append("sodium (number, mg)") }
        guard !parts.isEmpty else { return "" }
        return ", " + parts.joined(separator: ", ")
    }
}

extension CalorieBias {
    /// The instruction fragment injected into the `{bias}` slot of the system prompt. Kept here so
    /// the prompt vocabulary lives with the AI service, not scattered across call sites.
    var promptInstruction: String {
        let pct = abs(bufferPercent)
        let intensity = pct >= 20 ? "aggressive" : (pct >= 10 ? "moderate" : "slight")
        switch direction {
        case .over:
            return "overestimate: apply a +\(pct)% buffer to CALORIES, CARBS, and FAT only "
                + "(\(intensity), to protect the deficit). Do NOT inflate PROTEIN, keep it your honest "
                + "best estimate, because protein is a target the user wants to meet accurately and "
                + "padding it would falsely show the goal as met. Keep calories consistent with "
                + "4*protein + 4*carbs + 9*fat using the buffered carbs/fat."
        case .under:
            return "underestimate: trim CALORIES, CARBS, and FAT \(pct)% downward only "
                + "(\(intensity), to protect the surplus). Leave PROTEIN at your honest best estimate. "
                + "Keep calories consistent with 4*protein + 4*carbs + 9*fat using the trimmed carbs/fat."
        case .none:
            return "balanced: use the most accurate data available with NO buffer"
        }
    }
}

/// The raw per-item JSON shape both contracts share: macros keyed by short field names. Decoded then
/// mapped to the shared `LoggedFoodItem` via `asLoggedItem()`. Required macros throw if absent;
/// optional micros/extras default to nil/empty, never a fabricated value.
struct NutritionItemWire: Codable, Equatable, Sendable {
    var name: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var sugar: Double?
    var fiber: Double?
    var sodium: Double?
    var citations: [String]?
    var thoughtProcess: String?
    var confidenceScore: Int?

    init(from item: LoggedFoodItem) {
        name = item.name
        calories = item.calories
        protein = item.proteinG
        carbs = item.carbsG
        fat = item.fatG
        sugar = item.sugarG
        fiber = item.fiberG
        sodium = item.sodiumMg
        citations = item.citations.isEmpty ? nil : item.citations
        thoughtProcess = item.assumptions
        confidenceScore = item.confidenceScore
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        calories = try c.decode(Double.self, forKey: .calories)
        protein = try c.decode(Double.self, forKey: .protein)
        carbs = try c.decode(Double.self, forKey: .carbs)
        fat = try c.decode(Double.self, forKey: .fat)
        sugar = try c.decodeIfPresent(Double.self, forKey: .sugar)
        fiber = try c.decodeIfPresent(Double.self, forKey: .fiber)
        sodium = try c.decodeIfPresent(Double.self, forKey: .sodium)
        citations = try c.decodeIfPresent([String].self, forKey: .citations)
        thoughtProcess = try c.decodeIfPresent(String.self, forKey: .thoughtProcess)
        confidenceScore = try c.decodeIfPresent(Int.self, forKey: .confidenceScore)
    }

    /// Map the wire shape to the shared `LoggedFoodItem`, clamping confidence to 0…100.
    func asLoggedItem() -> LoggedFoodItem {
        LoggedFoodItem(
            name: name,
            calories: calories,
            proteinG: protein,
            carbsG: carbs,
            fatG: fat,
            sugarG: sugar,
            fiberG: fiber,
            sodiumMg: sodium,
            citations: citations ?? [],
            assumptions: thoughtProcess,
            confidenceScore: confidenceScore.map { min(100, max(0, $0)) }
        )
    }
}

/// The Sonar novel-food result: `{ "items": [ {…} ] }`.
struct SonarFoodResult: Codable, Equatable, Sendable {
    var items: [NutritionItemWire]
}

/// The Gemini edit/portion result: `{ "modifiedNutrition": { items: [ {…} ] } }`. We decode the
/// nested `items` (the source of truth) and ignore any model-supplied totals; the app re-sums from
/// items so the totals bar always equals the visible lines.
struct GeminiEditResult: Codable, Equatable, Sendable {
    var modifiedNutrition: ModifiedNutrition

    struct ModifiedNutrition: Codable, Equatable, Sendable {
        var items: [NutritionItemWire]
    }
}
