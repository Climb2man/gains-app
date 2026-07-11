import Foundation
import Observation

/// Retry policy tuning. Defaults: 3 attempts with a 0.5s base delay that doubles each retry (0.5s,
/// 1s, 2s). Injectable so tests can use near-zero delays.
struct RetryPolicy: Sendable {
    var maxAttempts: Int
    var baseDelay: Duration

    static let `default` = RetryPolicy(maxAttempts: 3, baseDelay: .milliseconds(500))

    /// The backoff before `attempt` (1-based): base · 2^(attempt-1).
    func delay(beforeAttempt attempt: Int) -> Duration {
        let exponent = max(0, attempt - 1)
        return baseDelay * (1 << exponent)
    }
}

@MainActor
@Observable
final class BackgroundTaskQueue {
    /// Jobs currently in flight; the UI can show a "filling in N" hint.
    private(set) var pendingCount = 0

    private let policy: RetryPolicy
    /// Live jobs by token, so re-enqueuing a token cancels its stale attempt (the user edited the line
    /// again before the first resolve landed) and teardown can cancel everything.
    private var jobs: [String: Task<Void, Never>] = [:]

    init(policy: RetryPolicy = .default) {
        self.policy = policy
    }

    /// Enqueue an async unit of work identified by `token`. `operation` performs the resolve and may
    /// throw to request a retry; `onSuccess` runs with its result on the MainActor; `onFailure` runs
    /// once retries are exhausted or `shouldRetry` vetoes the error (e.g. a missing API key, which
    /// retrying can't fix). Re-enqueuing the same token cancels the previous attempt first.
    func enqueue<Result: Sendable>(
        token: String,
        operation: @escaping @Sendable () async throws -> Result,
        onSuccess: @escaping @MainActor (Result) -> Void,
        onFailure: @escaping @MainActor (any Error) -> Void,
        shouldRetry: @escaping @Sendable (any Error) -> Bool = { _ in true }
    ) {
        jobs[token]?.cancel()
        pendingCount += 1

        let policy = self.policy
        let task = Task { @MainActor [weak self] in
            defer {
                self?.pendingCount = max(0, (self?.pendingCount ?? 1) - 1)
                self?.jobs[token] = nil
            }
            var lastError: any Error = CancellationError()
            for attempt in 1...max(1, policy.maxAttempts) {
                if Task.isCancelled { return }
                if attempt > 1 {
                    try? await Task.sleep(for: policy.delay(beforeAttempt: attempt))
                    if Task.isCancelled { return }
                }
                do {
                    let result = try await operation()
                    if Task.isCancelled { return }
                    onSuccess(result)
                    return
                } catch {
                    lastError = error
                    if !shouldRetry(error) { break }
                }
            }
            if !Task.isCancelled { onFailure(lastError) }
        }
        jobs[token] = task
    }

    /// Cancel one in-flight job (no-op if it already finished).
    func cancel(token: String) {
        jobs[token]?.cancel()
        jobs[token] = nil
    }

    /// Cancel every in-flight job (teardown). Pending counts reset as each job's `defer` runs.
    func cancelAll() {
        for task in jobs.values { task.cancel() }
        jobs.removeAll()
    }
}
