import Foundation

/// Runs scans one at a time and shares them between callers. A request waits for the next
/// scan that starts after it, never for one already running, so its answer is never stale;
/// everything requested while a scan runs is merged into one follow-up scan.
final class ScanCoordinator: @unchecked Sendable {
    private let queue: DispatchQueue
    private let perform: (ScanScope) -> Void
    private let lock = NSLock()
    private var pendingScope: ScanScope?
    private var waiters: [() -> Void] = []
    private var running = false
    private var scheduledScope: ScanScope?

    /// `perform` runs on `queue`.
    init(queue: DispatchQueue, perform: @escaping (ScanScope) -> Void) {
        self.queue = queue
        self.perform = perform
    }

    func scan(_ scope: ScanScope) async {
        await withCheckedContinuation { continuation in
            request(scope) { continuation.resume() }
        }
    }

    /// `completion` runs on the scan queue once a scan covering `scope` has finished.
    func request(_ scope: ScanScope, completion: @escaping () -> Void) {
        enqueue(scope, waiter: completion)
    }

    /// Scans after `delay`; requests scheduled before it fires join the same scan.
    func schedule(_ scope: ScanScope, after delay: Double) {
        lock.lock()
        let first = scheduledScope == nil
        scheduledScope = scheduledScope.map { $0.merged(with: scope) } ?? scope
        lock.unlock()
        guard first else { return }
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let scope = self.scheduledScope
            self.scheduledScope = nil
            self.lock.unlock()
            if let scope { self.enqueue(scope, waiter: nil) }
        }
    }

    private func enqueue(_ scope: ScanScope, waiter: (() -> Void)?) {
        lock.lock()
        pendingScope = pendingScope.map { $0.merged(with: scope) } ?? scope
        if let waiter { waiters.append(waiter) }
        let start = !running
        running = true
        lock.unlock()
        if start { queue.async { [self] in drain() } }
    }

    private func drain() {
        while true {
            lock.lock()
            guard let scope = pendingScope else {
                running = false
                lock.unlock()
                return
            }
            pendingScope = nil
            let answered = waiters
            waiters.removeAll()
            lock.unlock()
            perform(scope)
            answered.forEach { $0() }
        }
    }
}
