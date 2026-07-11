import CryptoKit
import XCTest
@testable import Gains

@MainActor
final class EncryptedFileStoreTests: XCTestCase {

    /// In-memory SecureStore, lets tests control key persistence without touching the real Keychain.
    private final class MemorySecureStore: SecureStore, @unchecked Sendable {
        var values: [String: String] = [:]
        var saveSucceeds = true

        @discardableResult func save(_ value: String, forKey key: String) -> Bool {
            guard saveSucceeds else { return false }
            values[key] = value
            return true
        }
        func read(_ key: String) -> String? { values[key] }
        @discardableResult func delete(_ key: String) -> Bool { values[key] = nil; return true }
    }

    private func isolatedDefaults(_ name: String) -> UserDefaults {
        let suiteName = "gains.test.encrypted-store.\(name)"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        return suite
    }

    private func makeStore(
        _ name: String,
        secure: MemorySecureStore = MemorySecureStore(),
        legacy: UserDefaults? = nil
    ) -> (store: EncryptedFileStore, secure: MemorySecureStore, legacy: UserDefaults) {
        let legacy = legacy ?? isolatedDefaults(name)
        let dirName = "GainsSecureStoreTests-\(name)"
        let base = try! FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        try? FileManager.default.removeItem(at: base.appendingPathComponent(dirName))
        let store = EncryptedFileStore(secureStore: secure, legacy: legacy, directoryName: dirName)
        return (store, secure, legacy)
    }

    func testRoundTripOverwriteAndRemove() {
        let (store, _, _) = makeStore("roundtrip")
        let key = "@gains/test/blob"

        XCTAssertNil(store.data(forKey: key))
        store.set(Data("hello health".utf8), forKey: key)
        XCTAssertEqual(store.data(forKey: key), Data("hello health".utf8))

        store.set(Data("second write".utf8), forKey: key)
        XCTAssertEqual(store.data(forKey: key), Data("second write".utf8), "overwrite replaces")

        store.removeValue(forKey: key)
        XCTAssertNil(store.data(forKey: key))
    }

    func testCiphertextOnDiskIsNotPlaintext() throws {
        let (store, _, _) = makeStore("ciphertext")
        let key = "@gains/test/phi"
        let secret = "salmon 650 kcal logged at noon"
        store.set(Data(secret.utf8), forKey: key)

        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        let dir = base.appendingPathComponent("GainsSecureStoreTests-ciphertext")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        let raw = try Data(contentsOf: files[0])
        XCTAssertNil(String(data: raw, encoding: .utf8)?.range(of: secret), "disk bytes must be ciphertext")
        XCTAssertFalse(raw.contains(Data(secret.utf8)), "plaintext bytes must not appear in the file")
        XCTAssertFalse(files[0].lastPathComponent.contains("phi"), "filenames must not leak the key")
    }

    func testTamperedFileReadsAsAbsentNeverGarbage() throws {
        let (store, _, _) = makeStore("tamper")
        let key = "@gains/test/tamper"
        store.set(Data("authentic value".utf8), forKey: key)

        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        let dir = base.appendingPathComponent("GainsSecureStoreTests-tamper")
        let file = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)[0]
        var raw = try Data(contentsOf: file)
        raw[raw.count - 1] ^= 0xFF
        try raw.write(to: file)

        XCTAssertNil(store.data(forKey: key), "a failed GCM tag check must read as absent")
    }

    func testKeyPersistsAcrossInstancesAndWrongKeyReadsNothing() {
        let secure = MemorySecureStore()
        let (first, _, legacy) = makeStore("keypersist", secure: secure)
        first.set(Data("written by first".utf8), forKey: "k")

        let second = EncryptedFileStore(secureStore: secure, legacy: legacy,
                                        directoryName: "GainsSecureStoreTests-keypersist")
        XCTAssertEqual(second.data(forKey: "k"), Data("written by first".utf8))

        let stranger = EncryptedFileStore(secureStore: MemorySecureStore(), legacy: legacy,
                                          directoryName: "GainsSecureStoreTests-keypersist")
        XCTAssertNil(stranger.data(forKey: "k"))
    }

    func testLazyMigrationDrainsLegacyPlaintext() {
        let legacy = isolatedDefaults("migration")
        let key = "@gains/nutrition/entries"
        legacy.set(Data("plaintext era blob".utf8), forKey: key)

        let (store, _, _) = makeStore("migration", legacy: legacy)
        XCTAssertEqual(store.data(forKey: key), Data("plaintext era blob".utf8))
        XCTAssertNil(legacy.data(forKey: key), "migration must remove the plaintext original")
        XCTAssertEqual(store.data(forKey: key), Data("plaintext era blob".utf8))
    }

    /// Regression: a FAILED ciphertext write must not take the plaintext original with it. The write can
    /// fail without throwing to the caller (file protection rejects a write before the device's first
    /// unlock after boot, which the widget and a background refresh both reach), and the migration used
    /// to remove the legacy copy unconditionally, leaving zero copies. Here the store's directory is
    /// deleted after init so `write(to:)` fails for the same observable reason.
    func testFailedMigrationWriteKeepsLegacyPlaintext() throws {
        let legacy = isolatedDefaults("failed-write")
        let key = "@gains/nutrition/entries"
        legacy.set(Data("the only copy".utf8), forKey: key)

        let (store, _, _) = makeStore("failed-write", legacy: legacy)
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        try FileManager.default.removeItem(at: base.appendingPathComponent("GainsSecureStoreTests-failed-write"))

        XCTAssertFalse(store.set(Data("anything".utf8), forKey: key), "a write that cannot land reports false")
        XCTAssertEqual(store.data(forKey: key), Data("the only copy".utf8), "the read still serves the legacy copy")
        XCTAssertEqual(legacy.data(forKey: key), Data("the only copy".utf8),
                       "a failed encrypted write must leave the plaintext original in place")
    }

    /// Regression: a launch running on an EPHEMERAL key must not overwrite ciphertext sealed by the
    /// durable key. The Keychain can refuse both the read and the write at once (locked device), which
    /// mints a fresh key while the durable one still exists. Writing then replaces the durable
    /// ciphertext atomically, and the next healthy launch cannot open what it finds: total data loss.
    func testEphemeralSessionDoesNotDestroyDurableCiphertext() {
        let secure = MemorySecureStore()
        let key = "@gains/nutrition/entries"
        let dirName = "GainsSecureStoreTests-ephemeral-clobber"
        let (durable, _, legacy) = makeStore("ephemeral-clobber", secure: secure)
        XCTAssertTrue(durable.set(Data("a year of meals".utf8), forKey: key))

        let lockedKeychain = MemorySecureStore()
        lockedKeychain.saveSucceeds = false
        let ephemeral = EncryptedFileStore(secureStore: lockedKeychain, legacy: legacy, directoryName: dirName)
        XCTAssertNil(ephemeral.data(forKey: key), "an ephemeral key cannot open the durable ciphertext")
        XCTAssertFalse(ephemeral.set(Data("this launch's data".utf8), forKey: key),
                       "an ephemeral key must refuse to overwrite ciphertext it cannot open")

        let recovered = EncryptedFileStore(secureStore: secure, legacy: legacy, directoryName: dirName)
        XCTAssertEqual(recovered.data(forKey: key), Data("a year of meals".utf8),
                       "the durable key must still open its own ciphertext on the next healthy launch")
    }

    func testWriteClearsAnyLegacyCopy() {
        let legacy = isolatedDefaults("write-clears")
        let key = "@gains/profile"
        legacy.set(Data("stale plaintext".utf8), forKey: key)

        let (store, _, _) = makeStore("write-clears", legacy: legacy)
        store.set(Data("fresh encrypted".utf8), forKey: key)
        XCTAssertNil(legacy.data(forKey: key), "a plaintext copy must never outlive an encrypted write")
        XCTAssertEqual(store.data(forKey: key), Data("fresh encrypted".utf8))
    }

    func testUnpersistableKeyStaysEphemeralNotPlaintext() throws {
        let secure = MemorySecureStore()
        secure.saveSucceeds = false
        let (store, _, _) = makeStore("ephemeral", secure: secure)
        store.set(Data("session-only".utf8), forKey: "k")

        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        let dir = base.appendingPathComponent("GainsSecureStoreTests-ephemeral")
        let raw = try Data(contentsOf: FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)[0])
        XCTAssertFalse(raw.contains(Data("session-only".utf8)))
        XCTAssertEqual(store.data(forKey: "k"), Data("session-only".utf8))
    }

    func testEphemeralSessionNeverDrainsLegacyAndHealthyLaunchStillMigrates() {
        let legacy = isolatedDefaults("ephemeral-preserve")
        legacy.set(Data("precious history".utf8), forKey: "@gains/profile")

        let broken = MemorySecureStore()
        broken.saveSucceeds = false
        let ephemeral = EncryptedFileStore(secureStore: broken, legacy: legacy,
                                           directoryName: "GainsSecureStoreTests-ephemeral-preserve")
        XCTAssertEqual(ephemeral.data(forKey: "@gains/profile"), Data("precious history".utf8))
        XCTAssertNotNil(legacy.data(forKey: "@gains/profile"), "ephemeral session must not drain legacy")
        ephemeral.set(Data("session edit".utf8), forKey: "@gains/profile")
        XCTAssertNotNil(legacy.data(forKey: "@gains/profile"))

        let healthy = EncryptedFileStore(secureStore: MemorySecureStore(), legacy: legacy,
                                         directoryName: "GainsSecureStoreTests-ephemeral-preserve")
        XCTAssertEqual(healthy.data(forKey: "@gains/profile"), Data("precious history".utf8))
        XCTAssertNil(legacy.data(forKey: "@gains/profile"), "the healthy launch completes the migration")
        XCTAssertEqual(healthy.data(forKey: "@gains/profile"), Data("precious history".utf8))
    }
}
