import Foundation

/// Runs main-actor work at a time on its clock. The app uses real time; tests use a clock that
/// only moves when told to.
@MainActor
protocol TabScheduler: AnyObject {
    /// Seconds on a monotonic clock.
    var now: TimeInterval { get }
    /// Runs `work` once `now` reaches `deadline`, unless cancelled first.
    func schedule(at deadline: TimeInterval, _ work: @escaping @MainActor () -> Void) -> TabScheduledWork
}

@MainActor
final class TabScheduledWork {
    private var onCancel: (() -> Void)?

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        onCancel?()
        onCancel = nil
    }
}

@MainActor
final class SystemTabScheduler: TabScheduler {
    var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func schedule(at deadline: TimeInterval, _ work: @escaping @MainActor () -> Void) -> TabScheduledWork {
        let delay = max(0, deadline - now)
        let task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            work()
        }
        return TabScheduledWork { task.cancel() }
    }
}
