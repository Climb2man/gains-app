import Foundation
import Security

/// A secret string store keyed by `String`, behind a protocol so tests can swap in a mock.
/// Synchronous: the underlying `SecItem*` calls are local and don't hit the network.
protocol SecureStore: Sendable {
    /// Store (or overwrite) the secret `value` under `key`. Returns `true` on success. Never logs `value`.
    @discardableResult func save(_ value: String, forKey key: String) -> Bool
    /// Read the secret stored under `key`, or `nil` if absent / unreadable. Never logs the value.
    func read(_ key: String) -> String?
    /// Delete the secret under `key`. Returns `true` if it was removed or already absent.
    @discardableResult func delete(_ key: String) -> Bool
}

/// The production `SecureStore` backed by the iOS keychain (`kSecClassGenericPassword`).
struct KeychainStore: SecureStore {
    /// The `kSecAttrService` namespace scoping all of Gains' items so they don't collide with other
    /// apps' generic-password items and can be queried as a group.
    private let service: String

    /// The access group every Gains item is stored under; must match a `keychain-access-groups` entry
    /// in `Gains.entitlements`. An unsigned simulator build (`CODE_SIGNING_ALLOWED=NO`) rejects
    /// `SecItem*` with `errSecMissingEntitlement` (-34018) unless the app declares an access group and
    /// the query targets it, so this is required for secrets to persist in DEBUG. `nil` falls back to
    /// the app's default group (signed builds).
    private let accessGroup: String?

    /// - Parameters:
    ///   - service: the keychain service namespace. Defaults to the app's bundle id so every Gains
    ///     secret lives under one service. Inject a different value in tests for isolation.
    ///   - accessGroup: the `keychain-access-groups` entry the items live under. Defaults to the group
    ///     declared in `Gains.entitlements` so an unsigned simulator build can read/write the keychain.
    init(
        service: String = Bundle.main.bundleIdentifier ?? "com.nxw.gains",
        accessGroup: String? = KeychainStore.defaultAccessGroup
    ) {
        self.service = service
        self.accessGroup = accessGroup
    }

    /// The access group the queries target, kept in one place so the entitlement and the queries can't
    /// drift apart. The unsigned simulator build must name the bare group from `Gains.entitlements`
    /// (without it `SecItem*` fails with -34018). A signed device build passes `nil` so the keychain
    /// uses the app's default group, the team-prefixed `$(AppIdentifierPrefix)com.nxw.gains.shared`
    /// from `Gains-Release.entitlements`; a bare runtime group would never match that value.
    #if targetEnvironment(simulator)
    static let defaultAccessGroup: String? = "com.nxw.gains.shared"
    #else
    static let defaultAccessGroup: String? = nil
    #endif

    /// The base query identifying one item: a generic password in our service (+ access group) under `key`.
    private func baseQuery(forKey key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    @discardableResult
    func save(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let query = baseQuery(forKey: key)
        let attributesToUpdate: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            return addStatus == errSecSuccess
        default:
            return false
        }
    }

    func read(_ key: String) -> String? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return value
    }

    @discardableResult
    func delete(_ key: String) -> Bool {
        let status = SecItemDelete(baseQuery(forKey: key) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
