import XCTest
@testable import Gains

final class WhoopTokenStoreTests: XCTestCase {

    /// In-memory keychain. Mirrors the real one's behaviour that matters here: a delete followed by a
    /// save re-ADDS the item rather than failing, which is what let a stale refresh resurrect a session.
    private final class MemoryKeychain: SecureStore, @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: String] = [:]

        @discardableResult func save(_ value: String, forKey key: String) -> Bool {
            lock.lock(); defer { lock.unlock() }
            values[key] = value
            return true
        }
        func read(_ key: String) -> String? {
            lock.lock(); defer { lock.unlock() }
            return values[key]
        }
        @discardableResult func delete(_ key: String) -> Bool {
            lock.lock(); defer { lock.unlock() }
            values[key] = nil
            return true
        }
    }

    /// Auth stub whose refresh suspends until the test releases it, so Disconnect can be run at the
    /// exact moment the token store is parked inside `await auth.refreshTokens`.
    private actor GatedAuth: WhoopAuthing {
        private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
        private var startWaiters: [CheckedContinuation<Void, Never>] = []
        private var hasStarted = false

        func initiateAuth(email: String, password: String) async -> WhoopCognitoLoginResult { .failed }

        func respondToMfa(
            challenge: WhoopMfaChallenge, session: String, username: String, code: String
        ) async -> WhoopCognitoTokens? { nil }

        func refreshTokens(refreshToken: String) async -> WhoopCognitoTokens? {
            hasStarted = true
            for waiter in startWaiters { waiter.resume() }
            startWaiters.removeAll()
            await withCheckedContinuation { releaseWaiters.append($0) }
            return WhoopCognitoTokens(
                accessToken: "refreshed-access",
                refreshToken: nil,
                expiresAt: Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000
            )
        }

        /// Resume once the store is actually suspended inside `refreshTokens`.
        func waitUntilRefreshStarted() async {
            if hasStarted { return }
            await withCheckedContinuation { startWaiters.append($0) }
        }

        func releaseRefresh() {
            for waiter in releaseWaiters { waiter.resume() }
            releaseWaiters.removeAll()
        }
    }

    private func storedSession(_ keychain: MemoryKeychain) -> WhoopSession? {
        guard let raw = keychain.read("gains.whoop.session"), let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WhoopSession.self, from: data)
    }

    /// Seed an EXPIRED session so the next `getValidAccessToken` is forced to refresh.
    private func seedStaleSession(_ keychain: MemoryKeychain, installationId: String = "install-1") {
        let stale = WhoopSession(
            accessToken: "stale-access",
            refreshToken: "refresh-1",
            expiresAt: Date().addingTimeInterval(-3600).timeIntervalSince1970 * 1000,
            installationId: installationId
        )
        let json = String(data: try! JSONEncoder().encode(stale), encoding: .utf8)!
        keychain.save(json, forKey: "gains.whoop.session")
    }

    /// Regression: Disconnect during an in-flight refresh must actually disconnect. `clearSession` used
    /// to drop the task handle without cancelling, so the refresh resumed and wrote the pre-disconnect
    /// session back into the keychain, silently relinking the user.
    func testDisconnectDuringRefreshDoesNotResurrectTheSession() async {
        let keychain = MemoryKeychain()
        let auth = GatedAuth()
        seedStaleSession(keychain)
        let store = WhoopTokenStore(keychain: keychain, auth: auth)

        let refreshing = Task { await store.getValidAccessToken() }
        await auth.waitUntilRefreshStarted()

        await store.clearSession()
        let linkedRightAfterDisconnect = await store.isLinked()
        XCTAssertFalse(linkedRightAfterDisconnect, "the session is gone the moment Disconnect runs")

        await auth.releaseRefresh()
        _ = await refreshing.value

        let linkedAfterRefreshLanded = await store.isLinked()
        XCTAssertFalse(linkedAfterRefreshLanded, "a refresh landing after Disconnect must not relink")
        XCTAssertNil(storedSession(keychain), "nothing may be written back into the keychain")
    }

    /// Regression: relinking a DIFFERENT account while a refresh is in flight must not have the old
    /// account's tokens clobber the new ones when that refresh lands.
    func testRefreshLandingAfterRelinkDoesNotClobberTheNewAccount() async {
        let keychain = MemoryKeychain()
        let auth = GatedAuth()
        seedStaleSession(keychain, installationId: "install-old")
        let store = WhoopTokenStore(keychain: keychain, auth: auth)

        let refreshing = Task { await store.getValidAccessToken() }
        await auth.waitUntilRefreshStarted()

        // The user disconnects and links a different account while the old refresh is parked.
        await store.clearSession()
        seedStaleSession(keychain, installationId: "install-new")

        await auth.releaseRefresh()
        _ = await refreshing.value

        XCTAssertEqual(storedSession(keychain)?.installationId, "install-new",
                       "the newly linked account must survive the old account's in-flight refresh")
    }

    /// The happy path still works: an uninterrupted refresh persists its result.
    func testUninterruptedRefreshPersistsTheNewToken() async {
        let keychain = MemoryKeychain()
        let auth = GatedAuth()
        seedStaleSession(keychain)
        let store = WhoopTokenStore(keychain: keychain, auth: auth)

        let refreshing = Task { await store.getValidAccessToken() }
        await auth.waitUntilRefreshStarted()
        await auth.releaseRefresh()

        let token = await refreshing.value
        XCTAssertEqual(token, "refreshed-access")
        XCTAssertEqual(storedSession(keychain)?.accessToken, "refreshed-access")
        XCTAssertEqual(storedSession(keychain)?.refreshToken, "refresh-1", "a nil refresh token keeps the old one")
    }
}
