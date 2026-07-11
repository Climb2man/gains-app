import Foundation
import Observation

@MainActor
@Observable
final class GainsMCPSync {
    private static let enabledKey = "@gains/mcp/enabled"
    private static let serverURLKey = "@gains/mcp/serverURL"
    private static let tokenKey = "@gains/mcp/syncToken"

    /// Whether cloud sync is on. Persisted. Re-pushes on launch so the slice stays fresh.
    private(set) var isEnabled = false
    /// The user's server origin, e.g. `https://your-server.example.com`. Persisted (not secret).
    var serverURLString = ""
    /// Whether a sync token is stored (the raw value never leaves the Keychain).
    private(set) var hasToken = false

    private(set) var isSyncing = false
    private(set) var lastSyncedAt: Date?
    private(set) var lastError: String?
    private(set) var lastSummary: String?

    private let secureStore: any SecureStore
    private let store: any KeyValueStore
    private let buildSlice: () async -> [String: Any]?
    private let session = URLSession(configuration: .ephemeral)
    /// The debounced push scheduled by `scheduleSync` (cancelled + replaced on each new change).
    private var pendingSync: Task<Void, Never>?

    init(
        secureStore: any SecureStore,
        store: any KeyValueStore = EncryptedFileStore.shared,
        buildSlice: @escaping () async -> [String: Any]?
    ) {
        self.secureStore = secureStore
        self.store = store
        self.buildSlice = buildSlice
        isEnabled = store.value(Bool.self, forKey: Self.enabledKey) ?? false
        serverURLString = store.value(String.self, forKey: Self.serverURLKey) ?? ""
        hasToken = secureStore.read(Self.tokenKey)?.isEmpty == false
    }

    /// The URL the user pastes into your assistant → Connectors → custom connector.
    var connectorURLString: String { normalizedBase.map { "\($0)/mcp" } ?? "" }

    /// True when there's enough config to actually sync.
    var isConfigured: Bool { normalizedBase != nil && hasToken }

    func setServerURL(_ raw: String) {
        serverURLString = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        store.setValue(serverURLString, forKey: Self.serverURLKey)
    }

    /// Store (or clear) the sync token: the same `MCP_AUTH_TOKEN` the server runs with.
    func setToken(_ raw: String) {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.isEmpty {
            secureStore.delete(Self.tokenKey)
            hasToken = false
        } else {
            secureStore.save(token, forKey: Self.tokenKey)
            hasToken = true
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        store.setValue(enabled, forKey: Self.enabledKey)
        if enabled {
            Task { await syncNow() }
        } else {
            // Turning sync OFF must also kill a debounced push that is already waiting. `scheduleSync`
            // sleeps 20s after the last edit, so without this a user who logs a meal and immediately
            // opts out still has that slice (food, workouts, Whoop recovery/HRV/sleep, weight, profile)
            // uploaded seconds later. `syncNow` re-checks `isEnabled` too, since the task can also be
            // mid-flight rather than merely scheduled.
            pendingSync?.cancel()
            pendingSync = nil
        }
    }

    /// Push once if the feature is on and configured. Called on app launch + on enable.
    func syncIfEnabled() async {
        guard isEnabled, isConfigured else { return }
        await syncNow()
    }

    /// Coalesce a burst of edits (logging a meal fires several change events) into one push shortly
    /// after the last change, so the MCP client sees fresh data without a push per keystroke.
    /// No-op unless opt-in and configured.
    func scheduleSync(after seconds: Double = 20) {
        guard isEnabled, isConfigured else { return }
        pendingSync?.cancel()
        pendingSync = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    /// Build the slice and POST it to /sync. Status-only errors (never content).
    func syncNow() async {
        // The opt-out is the gate on every push, not just the scheduled one. Callers reach this from a
        // debounced task and from the "Sync now" button, and the flag can flip while either is awaiting.
        guard isEnabled else { return }
        guard let base = normalizedBase, let token = secureStore.read(Self.tokenKey), !token.isEmpty else {
            lastError = "Add your server URL and sync token first."
            return
        }
        guard !isSyncing else { return }
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        guard let slice = await buildSlice(),
              let body = try? JSONSerialization.data(withJSONObject: slice) else {
            lastError = "Couldn't build your data slice."
            return
        }

        var request = URLRequest(url: base.appendingPathComponent("sync"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                lastError = "No response from the server."
                return
            }
            switch http.statusCode {
            case 200:
                lastSyncedAt = Date()
                lastSummary = Self.summarize(data)
            case 401, 403:
                lastError = "Server rejected the token (\(http.statusCode)). Check your sync token."
            case 400:
                lastError = "Server rejected the data (400). The app and server versions may differ."
            default:
                lastError = "Sync failed (HTTP \(http.statusCode))."
            }
        } catch {
            lastError = "Couldn't reach the server. Check the URL and your connection."
        }
    }

    /// Kill switch: tell the server to drop the slice from RAM, then forget the local token + disable.
    func wipeRemote() async {
        if let base = normalizedBase, let token = secureStore.read(Self.tokenKey), !token.isEmpty {
            var request = URLRequest(url: base.appendingPathComponent("sync"))
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await session.data(for: request)
        }
        setToken("")
        setEnabled(false)
        lastSyncedAt = nil
        lastSummary = nil
        lastError = nil
    }

    /// The server origin as a URL with no trailing slash, or nil if unusable.
    private var normalizedBase: URL? {
        var s = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        guard !s.isEmpty, let url = URL(string: s), url.scheme != nil, url.host != nil else { return nil }
        return url
    }

    /// A short, content-free summary of what the server reports it loaded.
    private static func summarize(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? [String: Any],
              let counts = status["counts"] as? [String: Any] else { return nil }
        let n = counts["nutrition_days"] as? Int ?? 0
        let w = counts["whoop_days"] as? Int ?? 0
        let k = counts["workout_days"] as? Int ?? 0
        return "\(n) days food · \(k) workouts · \(w) Whoop"
    }
}
