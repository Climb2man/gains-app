import XCTest
@testable import Gains

@MainActor
final class GainsMCPSyncTests: XCTestCase {

    /// In-memory SecureStore so the token lives nowhere near the real Keychain.
    private final class MemorySecureStore: SecureStore, @unchecked Sendable {
        var values: [String: String] = [:]
        @discardableResult func save(_ value: String, forKey key: String) -> Bool { values[key] = value; return true }
        func read(_ key: String) -> String? { values[key] }
        @discardableResult func delete(_ key: String) -> Bool { values[key] = nil; return true }
    }

    /// Counts slice builds. `syncNow` builds the slice before it POSTs, so "never built" is a precise
    /// stand-in for "nothing was uploaded" without reaching into the private URLSession.
    private final class BuildCounter: @unchecked Sendable {
        var count = 0
    }

    private func makeSync(counter: BuildCounter) -> GainsMCPSync {
        let suiteName = "gains.test.mcp-sync"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let secure = MemorySecureStore()
        secure.save("sync-token", forKey: "@gains/mcp/syncToken")

        let sync = GainsMCPSync(secureStore: secure, store: UserDefaultsStore(defaults: defaults)) {
            counter.count += 1
            return ["profile": [:]]
        }
        sync.setServerURL("https://gains.invalid")
        return sync
    }

    /// Regression: opting out must stop a push that is already queued. `scheduleSync` waits 20s after
    /// the last edit, so a user who logs a meal and immediately turns sync off used to have that slice
    /// (food, workouts, Whoop recovery/HRV/sleep, weight, profile) uploaded anyway. The debounced task
    /// is now cancelled on disable, and `syncNow` re-checks the flag in case it was already awaiting.
    func testDisabledSyncNeverBuildsOrUploadsASlice() async {
        let counter = BuildCounter()
        let sync = makeSync(counter: counter)
        XCTAssertFalse(sync.isEnabled, "sync is opt-in and starts off")
        XCTAssertTrue(sync.isConfigured, "URL and token are present, so only the opt-out blocks a push")

        await sync.syncNow()
        XCTAssertEqual(counter.count, 0, "a disabled sync must not build a slice, let alone upload one")
    }

    /// Turning sync back off after enabling it must also close the door: the flag is what gates every
    /// push, not just the scheduled one.
    func testOptingOutAfterEnablingBlocksFurtherPushes() async {
        let counter = BuildCounter()
        let sync = makeSync(counter: counter)

        sync.setEnabled(true)
        await sync.syncNow()
        let whileEnabled = counter.count
        XCTAssertGreaterThan(whileEnabled, 0, "an enabled, configured sync does build a slice")

        sync.setEnabled(false)
        sync.scheduleSync(after: 0)
        await sync.syncNow()
        XCTAssertEqual(counter.count, whileEnabled, "no slice may be built once the user has opted out")
    }
}
