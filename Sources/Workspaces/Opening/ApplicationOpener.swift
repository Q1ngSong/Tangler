import Foundation

/// Opens requests through an `OpenEnvironment` and turns its callback into one outcome: the
/// first reply, the timeout or cancellation, whichever comes first. A reply only counts when it
/// names the requested application, since macOS acknowledging a launch proves little else.
@MainActor
final class ApplicationOpener: ApplicationOpening {
    private let environment: OpenEnvironment
    private let timeout: Duration
    private let sleep: @Sendable (Duration) async throws -> Void

    /// A nil environment means NSWorkspace.
    init(environment: OpenEnvironment? = nil, timeout: Duration = .seconds(12),
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.environment = environment ?? .system
        self.timeout = timeout
        self.sleep = sleep
    }

    func isRunning(bundleID: String) -> Bool {
        environment.isRunning(bundleID)
    }

    func pid(bundleID: String) -> Int32? {
        environment.pid(bundleID)
    }

    func open(_ request: OpenRequest) async -> OpenOutcome {
        guard !Task.isCancelled else { return .cancelled }
        guard !request.bundleID.isEmpty, let applicationURL = environment.applicationURL(request.bundleID) else {
            return .applicationNotFound
        }
        let pending = PendingOpen()
        let outcome = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pending.continuation = continuation
                guard !Task.isCancelled else { return pending.finish(.cancelled) }
                let sleep = self.sleep, timeout = self.timeout
                pending.deadline = Task { @MainActor in
                    do { try await sleep(timeout) } catch { return }
                    pending.finish(.timedOut)
                }
                environment.open(request, applicationURL) { reply in
                    pending.finish(!reply.failed && reply.bundleID == request.bundleID ? .opened : .failed)
                }
            }
        } onCancel: {
            // An open macOS already accepted cannot be recalled; only the wait ends here.
            Task { @MainActor in pending.finish(.cancelled) }
        }
        return Task.isCancelled ? .cancelled : outcome
    }
}

/// Resumes its continuation once; later replies, deadlines and cancellations are ignored.
@MainActor
private final class PendingOpen {
    var continuation: CheckedContinuation<OpenOutcome, Never>?
    var deadline: Task<Void, Never>?

    func finish(_ outcome: OpenOutcome) {
        let waiting = continuation
        continuation = nil
        deadline?.cancel()
        deadline = nil
        waiting?.resume(returning: outcome)
    }
}
