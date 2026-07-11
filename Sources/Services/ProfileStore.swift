import Foundation
import Observation

/// Owns the loaded `Profile` and persists changes, plus the in-memory state that
/// drives the onboarding/profile screens.
@MainActor
@Observable
final class ProfileStore {
    /// Persistence key, kept stable so a future shared format stays compatible.
    private static let key = "gains.profile.v1"

    /// The current profile, or `nil` until onboarding completes (or if none is stored).
    private(set) var profile: Profile?

    private let store: any KeyValueStore

    /// - Parameter store: the persistence seam.
    /// Loads any saved profile synchronously on init so a view reads `profile` immediately.
    init(store: any KeyValueStore = EncryptedFileStore.shared) {
        self.store = store
        self.profile = store.value(Profile.self, forKey: Self.key)
    }

    /// Re-read the persisted profile (defensive: an absent/garbled blob → `nil`, never fabricated).
    func reload() {
        profile = store.value(Profile.self, forKey: Self.key)
    }

    /// Persist `profile` and update the in-memory copy.
    func save(_ profile: Profile) {
        self.profile = profile
        store.setValue(profile, forKey: Self.key)
    }

    /// Remove the stored profile (e.g. a reset/sign-out). The natural counterpart of save,
    /// kept here so callers don't reach past the seam.
    func clear() {
        profile = nil
        store.removeValue(forKey: Self.key)
    }
}
