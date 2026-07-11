import Foundation
import Observation

@MainActor
@Observable
final class SavedFoodsStore {
    private static let shortcutsKey = "@gains/foodlog/shortcuts"

    private(set) var shortcutsRaw: [FoodShortcut] = []

    private let store: any KeyValueStore

    init(store: any KeyValueStore = EncryptedFileStore.shared) {
        self.store = store
        load()
    }

    private func load() {
        if let stored = store.value([FoodShortcut].self, forKey: Self.shortcutsKey) {
            shortcutsRaw = stored
        }
    }

    private func persist(_ next: [FoodShortcut]) {
        shortcutsRaw = next
        store.setValue(next, forKey: Self.shortcutsKey)
    }

    /// Shortcuts ordered for the quick-add row + suggestions: pinned first (go-to meals stay on top
    /// regardless of use), then most-used, then most-recent. The view caps how many it shows.
    var shortcuts: [FoodShortcut] {
        shortcutsRaw.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            if a.useCount != b.useCount { return a.useCount > b.useCount }
            return a.updatedAt > b.updatedAt
        }
    }

    /// Whether a nickname already exists (normalized): lets the save UI offer "update" vs "create".
    func exists(nickname: String) -> Bool {
        let norm = Self.normalize(nickname)
        return shortcutsRaw.contains { Self.normalize($0.nickname) == norm }
    }

    /// Autocomplete matches for a partial nickname as the user types. Prefix matches
    /// rank above contains-matches; ties break by use_count. Empty query → the top suggestions.
    func autocomplete(_ query: String, limit: Int = 6) -> [FoodShortcut] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Array(shortcuts.prefix(limit)) }
        let matches = shortcutsRaw.filter { $0.nickname.localizedStandardContains(trimmed) }
        let ranked = matches.sorted { a, b in
            let aPrefix = a.nickname.lowercased().hasPrefix(trimmed.lowercased())
            let bPrefix = b.nickname.lowercased().hasPrefix(trimmed.lowercased())
            if aPrefix != bPrefix { return aPrefix }
            return a.useCount > b.useCount
        }
        return Array(ranked.prefix(limit))
    }

    /// The shortcut whose nickname exactly matches (normalized): the saved-foods-first hit the
    /// pipeline can consult before any AI call. Nil if none.
    func match(nickname: String) -> FoodShortcut? {
        let norm = Self.normalize(nickname)
        return shortcutsRaw.first { Self.normalize($0.nickname) == norm }
    }

    /// Save (or update) a shortcut from a resolved set of items. If the nickname
    /// already exists, its snapshot is refreshed in place (no duplicate) and `updatedAt` bumped.
    /// Returns the saved shortcut.
    @discardableResult
    func save(nickname: String, items: [LoggedFoodItem], source: String = "log") -> FoodShortcut {
        let now = Self.isoNow()
        let norm = Self.normalize(nickname)
        let snapshot = items.map { freshCopy(of: $0) }

        if let existing = shortcutsRaw.first(where: { Self.normalize($0.nickname) == norm }) {
            var updated = existing
            updated.nickname = nickname
            updated.items = snapshot
            updated.updatedAt = now
            persist(shortcutsRaw.map { $0.id == existing.id ? updated : $0 })
            return updated
        }

        let shortcut = FoodShortcut(
            nickname: nickname,
            items: snapshot,
            source: source,
            useCount: 0,
            createdAt: now,
            updatedAt: now
        )
        persist(shortcutsRaw + [shortcut])
        return shortcut
    }

    /// Rename a shortcut. No-op if the id is absent.
    func rename(id: String, to nickname: String) {
        persist(shortcutsRaw.map { shortcut in
            guard shortcut.id == id else { return shortcut }
            var renamed = shortcut
            renamed.nickname = nickname
            renamed.updatedAt = Self.isoNow()
            return renamed
        })
    }

    /// Edit a saved meal in place by id: rename and replace its snapshot (the Saved Meals edit form).
    /// Keeps `useCount`/`createdAt`/`isPinned`; bumps `updatedAt`. No-op if the id is absent.
    func update(id: String, nickname: String, items: [LoggedFoodItem]) {
        persist(shortcutsRaw.map { shortcut in
            guard shortcut.id == id else { return shortcut }
            var updated = shortcut
            updated.nickname = nickname
            updated.items = items.map { freshCopy(of: $0) }
            updated.updatedAt = Self.isoNow()
            return updated
        })
    }

    /// Pin / unpin a shortcut so it sorts to the top of the Saved Meals list. No-op if absent.
    func setPinned(id: String, _ pinned: Bool) {
        persist(shortcutsRaw.map { shortcut in
            guard shortcut.id == id else { return shortcut }
            var updated = shortcut
            updated.isPinned = pinned
            updated.updatedAt = Self.isoNow()
            return updated
        })
    }

    /// Bump usage after a shortcut is re-logged (orders the quick-add row). No-op if absent.
    func bumpUse(id: String) {
        persist(shortcutsRaw.map { shortcut in
            guard shortcut.id == id else { return shortcut }
            var bumped = shortcut
            bumped.useCount += 1
            bumped.updatedAt = Self.isoNow()
            return bumped
        })
    }

    /// Delete a shortcut (past log entries untouched, history stays honest).
    func remove(id: String) {
        persist(shortcutsRaw.filter { $0.id != id })
    }

    private func freshCopy(of item: LoggedFoodItem) -> LoggedFoodItem {
        var copy = item
        copy.id = UUID().uuidString
        return copy
    }

    /// Normalize a nickname for dedupe/match: trimmed, lowercased, inner whitespace collapsed.
    static func normalize(_ name: String) -> String {
        let lowered = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowered.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func isoNow() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: .now)
    }
}

#if DEBUG
extension SavedFoodsStore {
    /// DEBUG-only: seed shortcuts directly for previews/screenshots. Never used in a real build.
    func seed(_ shortcuts: [FoodShortcut]) {
        persist(shortcuts)
    }
}
#endif
