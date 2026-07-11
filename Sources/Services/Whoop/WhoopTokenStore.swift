import Foundation

/// Persisted session. Tokens + expiry + the stable per-install id. No password.
/// `Codable` for the JSON round-trip into the keychain.
struct WhoopSession: Codable, Sendable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Double
    let installationId: String

    /// True only when the required string fields are non-empty (a blank token blob is
    /// treated as "not linked").
    var isWellFormed: Bool {
        !accessToken.isEmpty && !refreshToken.isEmpty && !installationId.isEmpty
    }
}

/// The token-store surface the client depends on. Behind a protocol so the keychain +
/// auth dependencies are swappable in tests.
protocol WhoopSessionStore: Sendable {
    /// Persist freshly minted Cognito tokens as the active session (reusing or minting the
    /// installation id). Throws when there's no refresh token to persist.
    func saveTokens(_ tokens: WhoopCognitoTokens) async throws
    /// True if a well-formed private Whoop session is stored on this device.
    func isLinked() async -> Bool
    /// Wipe the stored session. Local-only; does not revoke at Whoop.
    func clearSession() async
    /// The stored installation id, or nil when not linked.
    func installationId() async -> String?
    /// A valid access token: cached when fresh, else single-flight-refreshed; nil when
    /// not linked or the refresh fails.
    func getValidAccessToken() async -> String?
}

/// Errors surfaced by the token store. Carries no secret material.
enum WhoopTokenStoreError: Error, Sendable {
    /// No refresh token anywhere: we can't persist a renewable session.
    case noRefreshToken
}

/// The concrete token store. An `actor` so the single-flight refresh and the
/// read/modify/write of the keychain blob are serialized.
actor WhoopTokenStore: WhoopSessionStore {
    /// Keychain key for the private Whoop session blob.
    private static let sessionKey = "gains.whoop.session"

    /// Refresh preemptively when the access token is within this of expiry (ms).
    private static let refreshSkewMs: Double = 60_000

    private let keychain: SecureStore
    private let auth: WhoopAuthing

    /// Single shared refresh task: all concurrent callers await the same one (the
    /// actor + this handle together provide single-flight behavior).
    private var inFlightRefresh: Task<WhoopSession?, Never>?

    /// - Parameters:
    ///   - keychain: the secure store (production: `KeychainStore`).
    ///   - auth: the Cognito client used for REFRESH_TOKEN_AUTH.
    init(keychain: SecureStore = KeychainStore(), auth: WhoopAuthing = WhoopAuth()) {
        self.keychain = keychain
        self.auth = auth
    }

    /// Read + validate the stored session, or nil if absent/corrupt. Never throws.
    private func readSession() -> WhoopSession? {
        guard let raw = keychain.read(Self.sessionKey),
              let data = raw.data(using: .utf8),
              let session = try? JSONDecoder().decode(WhoopSession.self, from: data),
              session.isWellFormed
        else { return nil }
        return session
    }

    /// Persist the session blob to the keychain. Returns whether the write succeeded so
    /// callers can decide whether to keep the in-memory value.
    @discardableResult
    private func writeSession(_ session: WhoopSession) -> Bool {
        guard let data = try? JSONEncoder().encode(session),
              let json = String(data: data, encoding: .utf8)
        else { return false }
        return keychain.save(json, forKey: Self.sessionKey)
    }

    /// Persist freshly minted Cognito tokens as the active session, reusing the existing
    /// installation id (or minting one on first login). `refreshToken` may be nil on a
    /// refresh response, in which case the prior refresh token is kept.
    func saveTokens(_ tokens: WhoopCognitoTokens) throws {
        let prior = readSession()
        guard let refreshToken = tokens.refreshToken ?? prior?.refreshToken else {
            throw WhoopTokenStoreError.noRefreshToken
        }
        let installationId = prior?.installationId ?? UUID().uuidString.uppercased()
        writeSession(WhoopSession(
            accessToken: tokens.accessToken,
            refreshToken: refreshToken,
            expiresAt: tokens.expiresAt,
            installationId: installationId
        ))
    }

    /// True if a well-formed private Whoop session is stored on this device.
    func isLinked() -> Bool {
        readSession() != nil
    }

    /// Wipe the stored session. Local-only; does not revoke at Whoop.
    func clearSession() {
        // CANCEL the refresh, don't merely drop the handle. This actor suspends inside
        // `auth.refreshTokens`, so a Disconnect can land mid-refresh; the resuming task would then
        // write the pre-disconnect session straight back, and `keychain.save` re-ADDs a deleted item
        // rather than failing, so the user would be silently relinked. `doRefresh` re-checks the
        // stored session before writing too, since cancellation is cooperative and may not be observed.
        inFlightRefresh?.cancel()
        inFlightRefresh = nil
        keychain.delete(Self.sessionKey)
    }

    /// Read the stored installation id, or nil when not linked.
    func installationId() -> String? {
        readSession()?.installationId
    }

    /// True when the cached access token is still comfortably valid.
    private func isFresh(_ session: WhoopSession) -> Bool {
        Date().timeIntervalSince1970 * 1000 < session.expiresAt - Self.refreshSkewMs
    }

    /// Return a valid access token: the cached one when fresh, otherwise a refreshed one
    /// (single-flight: a refresh already underway is awaited rather than started twice).
    /// Returns nil when not linked or the refresh fails. Never throws, never logs the
    /// token.
    func getValidAccessToken() async -> String? {
        guard let session = readSession() else { return nil }
        if isFresh(session) { return session.accessToken }

        let task: Task<WhoopSession?, Never>
        if let existing = inFlightRefresh {
            task = existing
        } else {
            task = Task { [weak self] in await self?.doRefresh(session) ?? nil }
            inFlightRefresh = task
        }
        let refreshed = await task.value
        if inFlightRefresh == task { inFlightRefresh = nil }
        return refreshed?.accessToken
    }

    /// Refresh the access token from the stored refresh token and re-persist. Cognito
    /// usually doesn't rotate the refresh token, so the old one is kept when no new one
    /// comes back.
    private func doRefresh(_ session: WhoopSession) async -> WhoopSession? {
        guard let next = await auth.refreshTokens(refreshToken: session.refreshToken) else {
            return nil
        }
        // The await above released actor isolation, so the stored session may have changed under us:
        // Disconnect deleted it, or the user relinked a DIFFERENT account. Persisting `session`'s
        // successor in either case would resurrect a session the user deleted, or clobber the new
        // account's tokens with the old account's. Only write when what is stored is still exactly
        // what this refresh started from.
        guard !Task.isCancelled, readSession() == session else { return nil }
        let updated = WhoopSession(
            accessToken: next.accessToken,
            refreshToken: next.refreshToken ?? session.refreshToken,
            expiresAt: next.expiresAt,
            installationId: session.installationId
        )
        writeSession(updated)
        return updated
    }
}
