import Contracts

/// Remembers the desktops last seen, to tell when their set changes: one added or removed, moved
/// in the order, or a full-screen Space come or gone. Which desktop is current does not count;
/// `.currentSpaceChanged` says that. Every change is announced once: a read of the Space list
/// that notices one counts it, and an operation that knows it changed the desktops announces the
/// change itself only when no read has done so since it began.
final class DesktopWatch: @unchecked Sendable {
    private struct State {
        var last: [SpaceInfo]?
        var changes = 0
    }

    private let state = Locked(State())

    /// How many changes have been announced; an operation takes it before it starts, for
    /// `claimsChange(since:)`.
    var changes: Int { state.value.changes }

    /// Takes a Space list just read; true when its desktops are not those last seen, which is to
    /// be announced. The first list seen is nothing to compare with, and an empty one could not
    /// be read: neither says anything.
    func noticesChange(in spaces: [SpaceInfo]) -> Bool {
        guard !spaces.isEmpty else { return false }
        let desktops = spaces.map { space -> SpaceInfo in
            var space = space
            space.isCurrent = false
            return space
        }
        return state.update { state in
            defer { state.last = desktops }
            guard let last = state.last, last != desktops else { return false }
            state.changes += 1
            return true
        }
    }

    /// For an operation that changed the desktops and took `changes` before it began: true when
    /// the change is still to be announced, because no read noticed one meanwhile, as when the
    /// list was never read before or cannot be read now.
    func claimsChange(since mark: Int) -> Bool {
        state.update { state in
            guard state.changes == mark else { return false }
            state.changes += 1
            return true
        }
    }
}
