import Contracts
import Foundation

/// Tells when a window that has been moving comes to rest (tab groups design 4.4): the left
/// button is up and no move arrived for `quiet` seconds. While the button is down it looks again
/// every `recheck` seconds, since a drag can pause without ending.
@MainActor
final class SettleTracker {
    static let quiet: TimeInterval = 0.15
    static let recheck: TimeInterval = 0.1

    private let scheduler: any TabScheduler
    private let isLeftButtonDown: () -> Bool
    private let settled: @MainActor (WindowID) -> Void
    private var pending: [WindowID: TabScheduledWork] = [:]

    init(scheduler: any TabScheduler, isLeftButtonDown: @escaping () -> Bool,
         settled: @escaping @MainActor (WindowID) -> Void) {
        self.scheduler = scheduler
        self.isLeftButtonDown = isLeftButtonDown
        self.settled = settled
    }

    /// Windows that moved and have not come to rest yet.
    var moving: Set<WindowID> { Set(pending.keys) }

    func moved(_ id: WindowID) { schedule(id, after: Self.quiet) }

    func forget(_ id: WindowID) { pending.removeValue(forKey: id)?.cancel() }

    func cancelAll() {
        for work in pending.values { work.cancel() }
        pending.removeAll()
    }

    private func schedule(_ id: WindowID, after delay: TimeInterval) {
        pending[id]?.cancel()
        pending[id] = scheduler.schedule(at: scheduler.now + delay) { [weak self] in self?.fire(id) }
    }

    private func fire(_ id: WindowID) {
        pending[id] = nil
        guard !isLeftButtonDown() else { return schedule(id, after: Self.recheck) }
        settled(id)
    }
}
