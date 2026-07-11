import XCTest
@testable import Gains

@MainActor
final class FoodFillRetryTests: XCTestCase {

    /// Scripted pipeline: throws the queued errors in order, then succeeds with `successItems`.
    /// `@MainActor` (like the production router) so the store's `@Sendable` operation can call it.
    @MainActor
    final class ScriptedFoodService: FoodLoggingService {
        var errors: [FoodLoggingError]
        let successItems: [LoggedFoodItem]
        private(set) var attempts = 0

        init(errors: [FoodLoggingError], successItems: [LoggedFoodItem] = []) {
            self.errors = errors
            self.successItems = successItems
        }

        func resolveLine(_ request: FoodLineRequest) async throws -> FoodLineResult {
            attempts += 1
            if !errors.isEmpty { throw errors.removeFirst() }
            return FoodLineResult(items: successItems)
        }

        func resolveEdit(_ request: FoodEditRequest) async throws -> FoodLineResult {
            attempts += 1
            if !errors.isEmpty { throw errors.removeFirst() }
            return FoodLineResult(items: successItems)
        }
    }

    /// An isolated, wiped UserDefaults suite per test so persisted state never leaks across runs.
    private func isolatedStore(_ name: String) -> UserDefaultsStore {
        let suiteName = "gains.test.fill-retry.\(name)"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        return UserDefaultsStore(defaults: suite)
    }

    /// A store wired with near-zero backoff so 3 attempts complete in milliseconds.
    private func makeStore(_ name: String, service: ScriptedFoodService) -> FoodLogStore {
        FoodLogStore(
            service: service,
            store: isolatedStore(name),
            fillQueue: BackgroundTaskQueue(policy: RetryPolicy(maxAttempts: 3, baseDelay: .milliseconds(1)))
        )
    }

    /// Pump the MainActor until `condition` holds (or ~2s passes, the assertions catch a timeout).
    private func waitUntil(_ condition: () -> Bool) async {
        var waited = 0
        while !condition() && waited < 2000 {
            try? await Task.sleep(for: .milliseconds(10))
            waited += 10
        }
    }

    func testTransientFailureRetriesThenResolves() async {
        let item = LoggedFoodItem(name: "Chicken bowl", calories: 400, proteinG: 35, carbsG: 30,
                                  fatG: 10, citations: [], confidenceScore: 70)
        let service = ScriptedFoodService(errors: [.transient, .transient], successItems: [item])
        let store = makeStore("retry-success", service: service)

        let id = store.logLine("chicken bowl", bias: .balanced, micronutrients: .off)
        await waitUntil { store.entries.first { $0.id == id }?.status == .resolved }

        let line = store.entries.first { $0.id == id }!
        XCTAssertEqual(service.attempts, 3, "two transient failures must earn two retries")
        XCTAssertEqual(line.items.map(\.name), ["Chicken bowl"], "the third attempt's REAL items land")
        XCTAssertEqual(line.items[0].calories, 400)
    }

    func testExhaustedRetriesLandTheOfflineFallback() async {
        let service = ScriptedFoodService(errors: [.transient, .transient, .transient])
        let store = makeStore("retry-exhaust", service: service)

        let id = store.logLine("mystery casserole", bias: .balanced, micronutrients: .off)
        await waitUntil { store.entries.first { $0.id == id }?.status == .resolved }

        let line = store.entries.first { $0.id == id }!
        XCTAssertEqual(service.attempts, 3, "all attempts must be spent before falling back")
        XCTAssertEqual(line.status, .resolved, "an offline fallback is a usable line, not a dead one")
        XCTAssertEqual(line.items[0].calories, 0, "never a fabricated number, zeroed for manual entry")
        XCTAssertEqual(line.items[0].confidenceScore, 0)
    }

    func testMissingKeyFailsFastWithoutRetry() async {
        let service = ScriptedFoodService(errors: [.missingKey, .missingKey, .missingKey])
        let store = makeStore("missing-key", service: service)

        let id = store.logLine("toast", bias: .balanced, micronutrients: .off)
        await waitUntil { store.entries.first { $0.id == id }?.status == .failed }

        XCTAssertEqual(service.attempts, 1, "a missing key must not burn backoff retries")
        XCTAssertEqual(store.entries.first { $0.id == id }?.status, .failed)
        XCTAssertEqual(store.notice, "Add your OpenRouter API key in Settings to estimate macros.")
    }

    func testFailedEditKeepsTheExistingNumbers() async {
        let service = ScriptedFoodService(errors: [.transient, .transient, .transient])
        let store = makeStore("edit-fallback", service: service)
        let original = LoggedFoodItem(name: "Burrito", calories: 720, proteinG: 52, carbsG: 74,
                                      fatG: 22, citations: [], confidenceScore: 68)
        let id = store.logCapturedLine(text: "burrito", items: [original])

        store.editLine(id: id, newText: "half a burrito", bias: .balanced, micronutrients: .off)
        await waitUntil { store.entries.first { $0.id == id }?.status == .resolved }

        let line = store.entries.first { $0.id == id }!
        XCTAssertEqual(line.items[0].calories, 720, "prior numbers beat zeroing when the edit can't resolve")
        XCTAssertEqual(line.items[0].confidenceScore, 0, "…but marked honestly as a fallback")
    }
}
