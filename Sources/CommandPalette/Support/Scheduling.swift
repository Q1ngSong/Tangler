/// Delayed work that can be called off.
@MainActor
final class ScheduledWork {
    private var onCancel: (() -> Void)?

    init(cancel: @escaping () -> Void) {
        onCancel = cancel
    }

    func cancel() {
        onCancel?()
        onCancel = nil
    }
}

/// Runs work after a delay. The linger period and notices go through it, so tests can
/// replace time with a scheduler they advance by hand.
@MainActor
protocol Scheduling: AnyObject {
    func schedule(after seconds: Double, _ work: @escaping @MainActor () -> Void) -> ScheduledWork
}

@MainActor
final class TaskScheduler: Scheduling {
    func schedule(after seconds: Double, _ work: @escaping @MainActor () -> Void) -> ScheduledWork {
        let task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            work()
        }
        return ScheduledWork { task.cancel() }
    }
}
