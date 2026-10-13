import CoreKit
import Contracts
import Foundation

/// Moves a window to another desktop and waits for the window server to confirm it.
/// Starting the operation proves nothing; only the window's Space membership counts.
final class SpaceMoves: @unchecked Sendable {
    struct Hooks {
        var spaces: () async -> [SpaceInfo]
        /// The Spaces showing a window; nil when that cannot be read.
        var membership: (WindowID) -> [SpaceID]?
        var record: (WindowID) -> WindowServerRecord?
        /// Starts the move and returns the operation, which must stay alive until confirmed.
        /// Runs on the main thread, as in the legacy app: nothing says SkyLight's bridged
        /// operation may be used from other threads. The operation is released there too.
        var start: @MainActor (WindowID, SpaceID) -> AnyObject?
        /// Waits between checks; false gives the wait up. The live one waits whether or not the
        /// task is cancelled and always answers true: the move is under way by then, and a wait
        /// that returned at once would say "not confirmed" of a move that lands.
        var pause: () async -> Bool
        var confirmed: (WindowID, [SpaceID]) -> Void
    }

    /// Carries the operation from the main thread, where it starts and ends, through the checks.
    private final class Operation: @unchecked Sendable {
        var object: AnyObject?

        init(_ object: AnyObject?) {
            self.object = object
        }
    }

    private let unavailableReason: () -> String?
    private let pollLimit: Int
    private let hooks: Hooks
    private let moving = Locked<Set<WindowID>>([])

    /// `unavailableReason` is nil when moving across Spaces is available.
    init(unavailableReason: @autoclosure @escaping () -> String?, pollLimit: Int = 30, hooks: Hooks) {
        self.unavailableReason = unavailableReason
        self.pollLimit = pollLimit
        self.hooks = hooks
    }

    func move(_ id: WindowID, to space: SpaceID) async -> Result<Void, WindowError> {
        if let unavailableReason = unavailableReason() { return .failure(.unsupported(unavailableReason)) }
        guard moving.update({ $0.insert(id).inserted }) else { return .failure(.rejected(L10n.text("windowkit.this.window.s.previous.move.has.not"))) }
        defer { moving.update { $0.remove(id) } }

        let desktops = await hooks.spaces().filter { !$0.isFullscreen }
        guard desktops.contains(where: { $0.id == space }) else { return .failure(.rejected(L10n.text("windowkit.the.target.desktop.does.not.exist.or"))) }
        guard let record = hooks.record(id), record.layer == 0, record.pid > 0 else { return .failure(.windowNotFound(id)) }
        guard let membership = hooks.membership(id), !membership.isEmpty else {
            return .failure(.rejected(L10n.text("windowkit.cannot.determine.which.desktop.contains.the.window")))
        }
        guard membership.count == 1, let original = membership.first, desktops.contains(where: { $0.id == original }) else {
            return .failure(.rejected(L10n.text("windowkit.only.windows.on.regular.desktops.can.be")))
        }
        if original == space { return .success(()) }

        let start = hooks.start
        let operation = await MainActor.run { Operation(start(id, space)) }
        guard operation.object != nil else {
            return .failure(.unsupported(L10n.text("windowkit.the.system.does.not.provide.an.api")))
        }
        let result = await confirm(id, arrivingAt: space, from: original)
        await MainActor.run { operation.object = nil }
        return result
    }

    private func confirm(_ id: WindowID, arrivingAt space: SpaceID, from original: SpaceID) async -> Result<Void, WindowError> {
        for _ in 0..<pollLimit {
            guard await hooks.pause() else { break }
            if let now = hooks.membership(id), now.contains(space), !now.contains(original) {
                hooks.confirmed(id, now)
                return .success(())
            }
        }
        return .failure(.rejected(L10n.text("windowkit.the.move.was.requested.but.arrival.on")))
    }
}
