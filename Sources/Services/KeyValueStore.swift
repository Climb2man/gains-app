import Foundation

/// A tiny string-keyed blob store. Synchronous fire-and-forget writes; payloads are small and local.
/// An encrypted-DB conformer can keep this signature (synchronous crypto), or the seam can go async later.
protocol KeyValueStore: Sendable {
    /// Raw bytes for `key`, or `nil` if absent.
    func data(forKey key: String) -> Data?
    /// Persist `data` under `key`, overwriting any previous value. Returns whether the value is now
    /// durably stored. A caller that is about to delete its only other copy of the bytes (the legacy
    /// migration in `EncryptedFileStore`) MUST check this: a false return means the write did not land
    /// and the source is still the sole copy. Discardable because most call sites are fire-and-forget.
    @discardableResult
    func set(_ data: Data, forKey key: String) -> Bool
    /// Remove any value for `key` (no-op if absent).
    func removeValue(forKey key: String)
}

extension KeyValueStore {
    /// Decode a Codable value under `key`. A missing key or undecodable blob returns `nil` (never throws).
    func value<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Encode and persist a Codable value under `key`. Returns false on an encode failure or a failed
    /// write, so a caller holding the only other copy can keep it.
    @discardableResult
    func setValue<T: Encodable>(_ value: T, forKey key: String) -> Bool {
        guard let data = try? JSONEncoder().encode(value) else { return false }
        return set(data, forKey: key)
    }
}

/// Plaintext conformer backed by `UserDefaults`, for DEBUG samples/previews and tests only
/// (production stores default to `EncryptedFileStore.shared`).
///
/// `@unchecked Sendable`: `UserDefaults` is thread-safe but the SDK doesn't mark it `Sendable`,
/// and these simple reads/writes are safe to cross actors.
struct UserDefaultsStore: KeyValueStore, @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    /// Always true: `UserDefaults` surfaces no write failure, and there is no second copy to protect.
    @discardableResult
    func set(_ data: Data, forKey key: String) -> Bool {
        defaults.set(data, forKey: key)
        return true
    }

    func removeValue(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}
