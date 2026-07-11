import Foundation

struct OpenRouterKeyStore: OpenRouterKeyProviding, Sendable {
    /// Keychain account for the user's OpenRouter key. Distinct, stable namespace under the app's
    /// service so it never collides with the Whoop session item.
    private static let keyId = "gains.openrouter.key"

    private let secureStore: any SecureStore

    init(secureStore: any SecureStore = KeychainStore()) {
        self.secureStore = secureStore
    }

    /// The user's OpenRouter key, or `nil` if none is stored. Satisfies `OpenRouterKeyProviding` so
    /// the provider fetches it per-call (revoking/rotating takes effect immediately).
    func openRouterKey() async throws -> String? {
        let value = secureStore.read(Self.keyId)
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    /// Persist (or overwrite) the user's key. Trims surrounding whitespace; refuses to store a blank.
    /// Returns `true` on success. Never logs the value.
    @discardableResult
    func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return secureStore.save(trimmed, forKey: Self.keyId)
    }

    /// Remove the stored key (e.g. a reset / rotate). Idempotent.
    @discardableResult
    func clear() -> Bool {
        secureStore.delete(Self.keyId)
    }

    /// Whether a key is stored. Reads only to test presence; the value is never surfaced.
    var hasKey: Bool {
        guard let value = secureStore.read(Self.keyId) else { return false }
        return !value.isEmpty
    }
}
