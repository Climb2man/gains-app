import CryptoKit
import Foundation

/// `@unchecked Sendable`: all stored properties are `let`, the file I/O and CryptoKit sealing are
/// thread-safe as used, and writes are atomic. Distinct stores use distinct keys, so there is no
/// same-key contention across actors.
final class EncryptedFileStore: KeyValueStore, @unchecked Sendable {
    /// The production instance every store defaults to: one master key, one directory.
    static let shared = EncryptedFileStore()

    private let masterKey: SymmetricKey
    /// False when the Keychain couldn't persist the key (ephemeral session). Migration must then leave
    /// the legacy plaintext in place; draining it into ciphertext only this session can read would
    /// destroy it for every later launch.
    private let masterKeyPersisted: Bool
    private let directory: URL
    /// The plaintext store this one supersedes; read once per key for lazy migration, then cleared.
    private let legacy: UserDefaults

    /// Keychain slot holding the base64 master key (a secret, not PHI: the `SecureStore` seam's job).
    private static let masterKeySlot = "gains.encrypted-store.master-key"

    /// - Parameters:
    ///   - secureStore: where the master key persists. Production: the iOS Keychain.
    ///   - legacy: the plaintext `UserDefaults` to lazily migrate from (and clear).
    ///   - directoryName: subdirectory of Application Support holding the ciphertext files.
    init(
        secureStore: any SecureStore = KeychainStore(),
        legacy: UserDefaults = .standard,
        directoryName: String = "GainsSecureStore"
    ) {
        (self.masterKey, self.masterKeyPersisted) = Self.loadOrCreateMasterKey(in: secureStore)
        self.legacy = legacy
        self.directory = Self.prepareDirectory(named: directoryName)
    }

    func data(forKey key: String) -> Data? {
        let url = fileURL(for: key)
        if let combined = try? Data(contentsOf: url),
           let box = try? AES.GCM.SealedBox(combined: combined),
           let plaintext = try? AES.GCM.open(box, using: masterKey) {
            return plaintext
        }
        guard let legacyData = legacy.data(forKey: key) else { return nil }
        // Drain the plaintext into ciphertext, but ONLY drop the plaintext once the ciphertext write
        // actually landed. `set` can fail without throwing: the file-protection class means a write
        // attempted before the device's first unlock after boot is rejected, which the widget and a
        // background refresh can both hit. Removing the legacy copy after a failed write would leave
        // no copy at all, silently losing the key's data on the next launch.
        if masterKeyPersisted, set(legacyData, forKey: key) {
            legacy.removeObject(forKey: key)
        }
        return legacyData
    }

    @discardableResult
    func set(_ data: Data, forKey key: String) -> Bool {
        let url = fileURL(for: key)
        // Running on an ephemeral key means the Keychain refused BOTH the read and the write this
        // launch (a locked device returns errSecInteractionNotAllowed, which `KeychainStore.save` maps
        // to false). The durable key usually still exists in the Keychain, so ciphertext already on
        // disk was sealed with it and this session cannot open it. Writing here is atomic, so it would
        // replace that file permanently: the next healthy launch loads the durable key, fails to open
        // what we wrote, and the legacy plaintext was drained long ago. Refuse rather than destroy.
        // A file this session CAN open is its own, so overwriting it is safe.
        if !masterKeyPersisted, isSealedByAnotherKey(at: url) { return false }
        guard let combined = try? AES.GCM.seal(data, using: masterKey).combined else { return false }
        do {
            try combined.write(to: url, options: [
                .atomic, .completeFileProtectionUntilFirstUserAuthentication,
            ])
        } catch {
            return false
        }
        if masterKeyPersisted {
            legacy.removeObject(forKey: key)
        }
        return true
    }

    func removeValue(forKey key: String) {
        try? FileManager.default.removeItem(at: fileURL(for: key))
        legacy.removeObject(forKey: key)
    }

    /// Load the persisted master key, or mint and persist one. Returns whether the key is durable: an
    /// unpersistable key (Keychain failure) stays ephemeral, and the migration paths above go read-only
    /// so no durable data is destroyed.
    private static func loadOrCreateMasterKey(in secureStore: any SecureStore) -> (SymmetricKey, persisted: Bool) {
        if let base64 = secureStore.read(masterKeySlot),
           let raw = Data(base64Encoded: base64), raw.count == 32 {
            return (SymmetricKey(data: raw), true)
        }
        let key = SymmetricKey(size: .bits256)
        let raw = key.withUnsafeBytes { Data($0) }
        let persisted = secureStore.save(raw.base64EncodedString(), forKey: masterKeySlot)
        if !persisted {
            print("[Gains] EncryptedFileStore: master key could not persist; running ephemeral this launch")
        }
        return (key, persisted)
    }

    /// Application Support/<name>/, created on first use and excluded from backups: the key can't leave
    /// the device, so backed-up ciphertext would be unrecoverable.
    private static func prepareDirectory(named name: String) -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        var dir = base.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        return dir
    }

    /// True when a file exists at `url` that this store's master key cannot open, meaning it was sealed
    /// by a different key and overwriting it would destroy data only that key can recover. A missing or
    /// unreadable file is not "another key's", so writing over it is allowed.
    private func isSealedByAnotherKey(at url: URL) -> Bool {
        guard let combined = try? Data(contentsOf: url) else { return false }
        guard let box = try? AES.GCM.SealedBox(combined: combined),
              (try? AES.GCM.open(box, using: masterKey)) != nil else { return true }
        return false
    }

    /// One file per key, named by the key's SHA-256 hex: path-safe and free of health-domain words.
    private func fileURL(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name)
    }
}
