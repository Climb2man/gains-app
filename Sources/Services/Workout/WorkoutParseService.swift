import Foundation

/// The workout-parse AI surface. A protocol so the store depends on intent, not wire shape, and tests can stub it.
protocol WorkoutParsing: Sendable {
    /// Parse a free-text workout into the canonical schema. Returns normalized exercises with an
    /// optional inferred title and a low-confidence flag. Throws `AIProviderError` on failure;
    /// never fabricates a result.
    func parse(_ text: String) async throws -> WorkoutParseResult
}

/// `WorkoutParsing` over the app's `AIProvider`: build prompt, decode, map. Transport and key
/// handling live inside the injected provider. Structured like `FoodAINutritionService`.
struct WorkoutParseService: WorkoutParsing {
    private let provider: any AIProvider

    init(provider: any AIProvider) {
        self.provider = provider
    }

    func parse(_ text: String) async throws -> WorkoutParseResult {
        let messages = [
            ChatMessage(.system, Self.systemPrompt),
            ChatMessage(.user, "Normalize this workout into the JSON schema:\n\(text)"),
        ]
        let raw = try await provider.completeJSON(messages: messages, lane: .cheap, maxTokens: 1200)
        let result: WorkoutParseWire = try Self.decode(raw)
        let exercises = result.exercises.map { $0.asExercise() }
        guard !exercises.isEmpty else { throw AIProviderError.decoding }
        return WorkoutParseResult(
            title: result.title?.trimmedNonEmpty,
            exercises: exercises,
            lowConfidence: result.lowConfidence ?? false
        )
    }

    /// Decode a strict-JSON model response into `T`; a non-decodable body throws `.decoding` rather
    /// than a fabricated value. Strips a leading JSON code fence via the food service's shared helper.
    private static func decode<T: Decodable>(_ raw: String) throws -> T {
        let cleaned = FoodAINutritionService.stripFence(raw)
        guard let data = cleaned.data(using: .utf8) else { throw AIProviderError.decoding }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw AIProviderError.decoding
        }
    }

    /// The normalization prompt: defines the output schema strictly, shows example input notations,
    /// and pins the safety and unit rules. The model returns one JSON object the wire contract decodes.
    static let systemPrompt: String =
        """
        You normalize a free-text gym workout into a STRICT JSON schema. The user may write in ANY \
        notation; do not assume a fixed format. Examples of notations you must handle (this list is \
        illustrative, not exhaustive): "3x10", "10@60", "60x10 lbs", "8,8,7@60", "bench 3x10 @135", \
        "incline DB 10,10,8 @50", supersets, drop sets, RPE (e.g. "@8 RPE"), warm-up sets, machine \
        names, bodyweight work, time/distance work, and kg or lb units. Infer the structure; never \
        invent numbers the text does not contain.

        Return ONE JSON object with this exact shape:
        {
          "title": string | null,          // a short session title if clearly implied (e.g. "Push day"), else null
          "lowConfidence": boolean,         // true if the notation was ambiguous and the user should verify
          "exercises": [
            {
              "name": string,               // the normalized, title-cased exercise name (expand abbreviations: "DB" -> "Dumbbell")
              "note": string | null,        // a short cue/machine/tempo note the user attached, else null
              "group": string | null,       // a superset/circuit tag (e.g. "A") when exercises are paired, else null
              "sets": [
                {
                  "reps": number | null,        // repetitions, or null for time/distance-only sets
                  "weight": number | null,      // the load as a number, or null for bodyweight
                  "weightUnit": string | null,  // the unit the user wrote ("lb"/"kg"); if a weight is present but no unit was stated, use "lb"; null for bodyweight
                  "rpe": number | null,         // RPE 0-10 if stated, else null
                  "isWarmup": boolean,          // true if the user marked it a warm-up
                  "isDropSet": boolean,         // true if it is a drop-set continuation
                  "raw": string                 // the user's original fragment for THIS set
                }
              ]
            }
          ]
        }

        Rules:
        - Expand a "NxM" shorthand (e.g. "3x10") into M reps repeated across N sets unless a weight or \
          per-set detail makes another reading clearer.
        - A comma list of reps (e.g. "8,8,7@60") is one set per number, each at the shared weight.
        - Preserve the unit the user typed; default to "lb" only when a weight is present with no unit.
        - This is the user's OWN logged training data, normalized for their record. Do NOT give advice, \
          coaching, programming, or any medical/prescriptive commentary. Structure only.
        - Output JSON only, no prose, no code fence.
        """
}

/// The raw JSON shape the model returns, decoded then mapped to the shared app shapes. The exercise
/// name is required; every other field is optional and defaults safely to nil/false.
private struct WorkoutParseWire: Codable, Sendable {
    var title: String?
    var lowConfidence: Bool?
    var exercises: [ExerciseWire]

    struct ExerciseWire: Codable, Sendable {
        var name: String
        var note: String?
        var group: String?
        var sets: [SetWire]?

        func asExercise() -> WorkoutExercise {
            WorkoutExercise(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                note: note?.trimmedNonEmpty,
                group: group?.trimmedNonEmpty,
                sets: (sets ?? []).map { $0.asSet() }
            )
        }
    }

    struct SetWire: Codable, Sendable {
        var reps: Int?
        var weight: Double?
        var weightUnit: String?
        var rpe: Double?
        var isWarmup: Bool?
        var isDropSet: Bool?
        var raw: String?

        func asSet() -> WorkoutSet {
            let clampedRPE = rpe.map { min(10, max(0, $0)) }
            let unit: String?
            if let weightUnit = weightUnit?.trimmedNonEmpty {
                unit = weightUnit
            } else if weight != nil {
                unit = "lb"
            } else {
                unit = nil
            }
            return WorkoutSet(
                reps: reps,
                weight: weight,
                weightUnit: unit,
                rpe: clampedRPE,
                isWarmup: isWarmup ?? false,
                isDropSet: isDropSet ?? false,
                raw: raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
        }
    }
}

private extension String {
    /// The trimmed string, or nil when empty after trimming, so a blank model output becomes a clean nil.
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
