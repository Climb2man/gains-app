import Foundation
import Observation

/// One cached base-nutrition record. `baseItems` is the resolved snapshot the line first produced;
/// `sourceModel` records which model/source produced it (provenance, never a key).
struct NutritionCacheRecord: Codable, Equatable, Sendable {
    /// The normalized text key (also the dictionary key; stored here for round-tripping).
    var normalizedText: String
    /// The base resolved items the line first resolved into (carry their own macros + citations).
    var baseItems: [LoggedFoodItem]
    /// Model/source id that produced this (e.g. `perplexity/sonar`, `openfoodfacts`). Never a key.
    var sourceModel: String
    /// ISO 8601 timestamp of when it was cached.
    var createdAt: String
}

/// The local nutrition cache. `@MainActor @Observable` to match the other on-device stores; the
/// read/write surface is small and synchronous.
@MainActor
@Observable
final class NutritionCache {
    private static let storeKey = "@gains/foodlog/nutrition-cache"

    /// All records keyed by normalized text. Loaded once at init, written through on each upsert.
    private(set) var records: [String: NutritionCacheRecord] = [:]

    private let store: any KeyValueStore

    init(store: any KeyValueStore = EncryptedFileStore.shared) {
        self.store = store
        if let stored = store.value([String: NutritionCacheRecord].self, forKey: Self.storeKey) {
            records = stored
        }
    }

    /// Normalize text to a cache key: trim, lowercase, collapse inner whitespace. Reuses the same rule
    /// `SavedFoodsStore` uses for nickname dedupe so the two never disagree.
    static func normalize(_ text: String) -> String {
        SavedFoodsStore.normalize(text)
    }

    /// Look up a record by raw text (normalizes internally). `nil` on a miss, so the router falls to the
    /// bundled-DB / novel path.
    func record(for rawText: String) -> NutritionCacheRecord? {
        records[Self.normalize(rawText)]
    }

    /// Cache (or overwrite) the base nutrition for a line. Called after a novel Sonar resolve or a
    /// bundled-DB match.
    func store(rawText: String, baseItems: [LoggedFoodItem], sourceModel: String) {
        let key = Self.normalize(rawText)
        guard !key.isEmpty, !baseItems.isEmpty else { return }
        records[key] = NutritionCacheRecord(
            normalizedText: key,
            baseItems: baseItems,
            sourceModel: sourceModel,
            createdAt: Self.isoNow()
        )
        persist()
    }

    /// Remove one record (e.g. a Settings "forget this food"). No-op if absent.
    func remove(rawText: String) {
        records.removeValue(forKey: Self.normalize(rawText))
        persist()
    }

    /// Clear the whole cache (Settings "reset cache").
    func clear() {
        records = [:]
        persist()
    }

    private func persist() {
        store.setValue(records, forKey: Self.storeKey)
    }

    private static func isoNow() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: .now)
    }
}
