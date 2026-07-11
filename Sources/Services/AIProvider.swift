import Foundation

/// Supplies the user's OpenRouter API key from secure storage.
///
/// Defined here so this module compiles independently of the Keychain layer; the production
/// conformer is a thin adapter over `KeychainStore`, and tests pass an in-memory stub. Returns `nil`
/// when no key is stored. Callers prompt the user in Settings and never log the key.
protocol OpenRouterKeyProviding: Sendable {
    /// The user's OpenRouter key, or `nil` if none is stored. Throws only on a Keychain access error.
    func openRouterKey() async throws -> String?
}

/// Roles in a chat exchange. Mirrors the OpenRouter / OpenAI `messages[].role` field.
enum ChatRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

/// One part of a message's content: plain text, or (for vision) text mixed with an inline base64
/// image. Mirrors the OpenAI/OpenRouter `content` part union. The image travels only inside the one
/// vision request, on the user's own key, and is never logged.
enum ChatContentPart: Sendable {
    /// A text fragment (a prompt, or text accompanying an image).
    case text(String)
    /// An inline image as a `data:` URL: `data:<mimeType>;base64,<base64>`. Built locally from a
    /// JPEG the caller compressed; carries no key and no identity.
    case imageData(base64: String, mimeType: String)
}

/// One message in a chat request. `content` is an ordered list of parts (usually a single `.text`;
/// a vision message interleaves `.text` + `.imageData`). Encodes to a bare `String` for a lone text
/// part (back-compat with the text pipeline) and to the OpenAI parts array otherwise.
struct ChatMessage: Codable, Sendable {
    var role: ChatRole
    var content: [ChatContentPart]

    /// Plain-text message: the common case, source-compatible with every existing text call site.
    init(_ role: ChatRole, _ content: String) {
        self.role = role
        self.content = [.text(content)]
    }

    /// A multi-part message (text + inline image) for the vision lane.
    init(_ role: ChatRole, parts: [ChatContentPart]) {
        self.role = role
        self.content = parts
    }

    private enum CodingKeys: String, CodingKey { case role, content }
    private enum PartKeys: String, CodingKey { case type, text, imageURL = "image_url" }
    private enum ImageURLKeys: String, CodingKey { case url }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        if content.count == 1, case let .text(text) = content[0] {
            try container.encode(text, forKey: .content)
            return
        }
        var parts = container.nestedUnkeyedContainer(forKey: .content)
        for part in content {
            var partContainer = parts.nestedContainer(keyedBy: PartKeys.self)
            switch part {
            case let .text(text):
                try partContainer.encode("text", forKey: .type)
                try partContainer.encode(text, forKey: .text)
            case let .imageData(base64, mimeType):
                try partContainer.encode("image_url", forKey: .type)
                var imageContainer = partContainer.nestedContainer(keyedBy: ImageURLKeys.self, forKey: .imageURL)
                try imageContainer.encode("data:\(mimeType);base64,\(base64)", forKey: .url)
            }
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(ChatRole.self, forKey: .role)
        if let text = try? container.decode(String.self, forKey: .content) {
            content = [.text(text)]
        } else {
            content = []
        }
    }
}

/// Which configured model to use. Model IDs are config, not hard-coded at call sites: a caller picks
/// a lane by intent and `AIModels` resolves it to an id (overridable in Settings).
enum ModelLane: Sendable {
    /// Novel / web-grounded foods: returns citations (`perplexity/sonar`). The expensive path.
    case novel
    /// Edits, portions, cache recalc, vision: `google/gemini-2.5-flash-lite`. The cheap path.
    case cheap

    /// Whether the lane's model accepts OpenAI-style `response_format: { type: "json_object" }`.
    /// Gemini (`.cheap`) does; Sonar (`.novel`) rejects it with a 400 and its output degrades, so we
    /// omit it there and rely on the prompt's "Output JSON only" instruction.
    var requestsJSONObjectFormat: Bool {
        switch self {
        case .novel: false
        case .cheap: true
        }
    }
}

/// The thin AI seam. One structured JSON call: send messages, get raw response text back. Higher
/// layers (FoodAINutritionService) own prompt construction and decoding so this stays format-only.
protocol AIProvider: Sendable {
    /// Performs a chat-completion request that asks the model for a JSON object response, returning the
    /// model's raw message text (expected to be a JSON document the caller decodes).
    ///
    /// - Parameters:
    ///   - messages: the conversation (system + user turns).
    ///   - lane: which configured model to use.
    ///   - maxTokens: response cap.
    /// - Returns: the assistant message content (a JSON string), to be decoded by the caller.
    /// - Throws: `AIProviderError` for missing-key / HTTP / decode failures. No thrown error ever
    ///   contains the API key.
    func completeJSON(
        messages: [ChatMessage],
        lane: ModelLane,
        maxTokens: Int
    ) async throws -> String
}

extension AIProvider {
    /// Convenience: default a sensible token cap so call sites stay terse.
    func completeJSON(messages: [ChatMessage], lane: ModelLane) async throws -> String {
        try await completeJSON(messages: messages, lane: lane, maxTokens: 512)
    }

    /// Vision convenience: send a system instruction plus a user message pairing a text prompt with
    /// one inline base64 image, and get the model's raw JSON back. Pinned to the `.cheap` lane so
    /// vision never routes to the expensive Sonar lane. A thin wrapper over `completeJSON`. The image
    /// travels only inside this request, on the user's own key, and is never logged.
    ///
    /// - Parameters:
    ///   - system: the system instruction (the JSON contract the model must return).
    ///   - prompt: the user text accompanying the image.
    ///   - imageBase64: the JPEG bytes, base64-encoded, the caller already compressed locally.
    ///   - mimeType: the image MIME type (default `image/jpeg`).
    ///   - maxTokens: response cap (vision results can be longer than a single text line).
    /// - Returns: the assistant message content (a JSON string), to be decoded by the caller.
    /// - Throws: `AIProviderError` (incl. `.missingKey`); no thrown error ever carries the key or image.
    func completeVisionJSON(
        system: String,
        prompt: String,
        imageBase64: String,
        mimeType: String = "image/jpeg",
        maxTokens: Int = 900
    ) async throws -> String {
        let messages = [
            ChatMessage(.system, system),
            ChatMessage(.user, parts: [
                .text(prompt),
                .imageData(base64: imageBase64, mimeType: mimeType),
            ]),
        ]
        return try await completeJSON(messages: messages, lane: .cheap, maxTokens: maxTokens)
    }
}

/// Provider-level failures. No case ever carries the API key: only safe, user-facing context (an
/// HTTP status, a parse note). The macro estimator catches these and falls back offline.
enum AIProviderError: Error, Equatable, Sendable {
    /// The user hasn't added an OpenRouter key yet. Prompt them to add one in Settings.
    case missingKey
    /// The request failed at the network layer (no/garbled response).
    case network
    /// The server returned a non-2xx status (status code only, never the body, which could echo
    /// request content; and never the key).
    case http(status: Int)
    /// The response body wasn't the expected shape (no decodable assistant content).
    case decoding
}

/// Resolves a `ModelLane` to a concrete OpenRouter model id. Both defaults are overridable in
/// Settings. Pass overrides at construction so call sites stay untouched.
struct AIModels: Sendable {
    /// Novel / web-grounded model (citations). Default `perplexity/sonar`.
    var novel: String
    /// Cheap / vision / edits model. Default `google/gemini-2.5-flash-lite`.
    var cheap: String

    static let `default` = AIModels(novel: "perplexity/sonar", cheap: "google/gemini-2.5-flash-lite")

    func id(for lane: ModelLane) -> String {
        switch lane {
        case .novel: return novel
        case .cheap: return cheap
        }
    }
}

/// `AIProvider` backed by OpenRouter's OpenAI-compatible chat-completions endpoint.
///
/// POSTs to `/api/v1/chat/completions` with `Authorization: Bearer <key>` and a JSON body of
/// `{ model, messages, response_format?, max_tokens }`. The key is fetched per-call from the
/// `OpenRouterKeyProviding` seam (so rotating it in Settings takes effect immediately) and used only
/// to build the header.
struct OpenRouterProvider: AIProvider {
    private let keyProvider: any OpenRouterKeyProviding
    private let models: AIModels
    private let session: URLSession
    private let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    init(
        keyProvider: any OpenRouterKeyProviding,
        models: AIModels = .default,
        session: URLSession = .shared
    ) {
        self.keyProvider = keyProvider
        self.models = models
        self.session = session
    }

    func completeJSON(
        messages: [ChatMessage],
        lane: ModelLane,
        maxTokens: Int
    ) async throws -> String {
        guard let key = try await keyProvider.openRouterKey(), !key.isEmpty else {
            #if DEBUG
            print("[Gains][DEBUG] AI request skipped: no OpenRouter key in the Keychain.")
            #endif
            throw AIProviderError.missingKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("https://gains.app", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Gains", forHTTPHeaderField: "X-Title")

        let payload = RequestBody(
            model: models.id(for: lane),
            messages: messages,
            responseFormat: lane.requestsJSONObjectFormat ? .jsonObject : nil,
            maxTokens: maxTokens
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            #if DEBUG
            print("[Gains][DEBUG] AI request transport error (no network / TLS / timeout).")
            #endif
            throw AIProviderError.network
        }

        guard let http = response as? HTTPURLResponse else { throw AIProviderError.network }
        guard (200..<300).contains(http.statusCode) else {
            #if DEBUG
            print("[Gains][DEBUG] AI request failed: HTTP \(http.statusCode) from OpenRouter.")
            #endif
            throw AIProviderError.http(status: http.statusCode)
        }

        let decoded: ChatCompletionResponse
        do {
            decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        } catch {
            throw AIProviderError.decoding
        }
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw AIProviderError.decoding
        }
        return content
    }
}

/// The request body. `response_format: { type: "json_object" }` asks for strict-JSON output, sent
/// only on lanes whose model supports it (Gemini) and omitted (`nil`) on the Sonar lane, which
/// rejects it.
private struct RequestBody: Encodable {
    let model: String
    let messages: [ChatMessage]
    let responseFormat: ResponseFormat?
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model, messages
        case responseFormat = "response_format"
        case maxTokens = "max_tokens"
    }

    struct ResponseFormat: Encodable {
        let type: String
        static let jsonObject = ResponseFormat(type: "json_object")
    }
}

/// Minimal envelope decoded from the chat-completions response: we read only
/// `choices[0].message.content` and ignore the rest. A missing field surfaces as a decode error
/// (`AIProviderError.decoding`), never a fabricated value.
private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message
    }
    let choices: [Choice]
}
