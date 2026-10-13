import CoreKit
import Contracts

/// Which window to focus so that macOS goes to its desktop (workspaces design 7.3).
enum DesktopSwitch {
    /// `preferred` when it is on `space` alone and can take focus, else the first listed window
    /// that is. A window on several desktops brings none of them, and a minimized one would have
    /// to be restored first.
    static func window(toFocusOn space: SpaceID, among windows: [WindowInfo], preferring preferred: WindowID?) -> WindowID? {
        let able = windows.filter { $0.spaceIDs == [space] && !$0.isMinimized }.map(\.id)
        return able.first { $0 == preferred } ?? able.first
    }
}

/// Goes to an ordinary desktop: with Dock swipes when it is on the display's own row of Spaces
/// (`DesktopSwiper`), else, or from wherever the swipes stopped, by focusing a window that is on
/// it alone, and through Mission Control when it has none or when focusing did not take the
/// screen there (workspaces design 7.3). A focus that reports success proves nothing; only the
/// Space list says where the screen is. A focus that failed only because the application did not
/// confirm in time is waited for like one that succeeded. When the desktop is not reached,
/// keyboard focus goes back to the window that had it, so that keystrokes do not go to a window
/// on a desktop that is not showing. Cancellation is never looked at: a switch back home that
/// rolls a cancelled task's work back runs like any other.
final class DesktopSwitcher: @unchecked Sendable {
    struct Hooks {
        /// Every Space, full-screen ones included. An empty list means the Spaces could not be read.
        var spaces: () async -> [SpaceInfo]
        /// The fast way: true when Dock swipes took the screen to the desktop. False says nothing
        /// about where the screen is now.
        var swipe: (SpaceID) async -> Bool
        var windows: () async -> [WindowInfo]
        /// The window that has keyboard focus.
        var focusedWindow: () async -> WindowID?
        var focus: (WindowID) async -> Result<Void, WindowError>
        /// The Mission Control route, for a desktop no window leads to.
        var show: (SpaceID) async -> Result<Void, WindowError>
        /// Waits between checks. It has to wait even when the task is cancelled: the flow runs to
        /// its end and puts the focus back if it must.
        var pause: () async -> Void
    }

    private let pollLimit: Int
    private let hooks: Hooks

    /// The wait for a focused window to bring its desktop gives up after `pollLimit` pauses:
    /// 2 seconds with the live 50 ms pause. macOS reports a switch only once its animation ended.
    init(pollLimit: Int = 40, hooks: Hooks) {
        self.pollLimit = pollLimit
        self.hooks = hooks
    }

    /// Success exactly when `space` is the current desktop at the end. `preferred` is the window
    /// to focus there when it can bring the desktop; see `DesktopSwitch`.
    func switchTo(_ space: SpaceID, focusing preferred: WindowID?) async -> Result<Void, WindowError> {
        let all = await hooks.spaces()
        guard !all.isEmpty else { return .failure(.rejected(L10n.text("windowkit.could.not.read.the.desktop.list"))) }
        guard let target = all.first(where: { $0.id == space && !$0.isFullscreen }) else {
            return .failure(.rejected(L10n.text("windowkit.the.target.desktop.does.not.exist.or")))
        }
        if target.isCurrent { return .success(()) }
        if await hooks.swipe(space), await isCurrent(space) {
            // The system gives the desktop its own last focus back; only a window the caller
            // names, and that is there, is focused.
            if let preferred, await hooks.windows().contains(where: {
                $0.id == preferred && $0.spaceIDs.contains(space) && !$0.isMinimized
            }) {
                _ = await hooks.focus(preferred)
            }
            return .success(())
        }
        // The swipes may have stopped on the way, or landed late.
        if await isCurrent(space) { return .success(()) }

        var previous: WindowID?
        // Whether a focus request went out, whatever it answered: one that reported failure can
        // still land.
        var asked = false
        if let candidate = DesktopSwitch.window(toFocusOn: space, among: await hooks.windows(), preferring: preferred) {
            previous = await hooks.focusedWindow()
            asked = true
            let focused = await hooks.focus(candidate)
            // Only a window that is gone or a refusal for lack of permission brings no desktop. Any
            // other failure may be the focus giving up on an application's late confirmation while
            // the desktop switch is still animating: Mission Control must not open in the middle of it.
            if !Self.bringsNoDesktop(focused), await arrives(at: space) { return .success(()) }
        }
        let shown = await hooks.show(space)
        if await isCurrent(space) { return .success(()) }
        if asked, let previous { _ = await hooks.focus(previous) }
        if case .failure(let error) = shown { return .failure(error) }
        return .failure(.rejected(L10n.text("windowkit.could.not.switch.to.the.target.desktop")))
    }

    private static func bringsNoDesktop(_ result: Result<Void, WindowError>) -> Bool {
        switch result {
        case .failure(.windowNotFound), .failure(.notAuthorized): return true
        default: return false
        }
    }

    private func arrives(at space: SpaceID) async -> Bool {
        for _ in 0..<pollLimit {
            if await isCurrent(space) { return true }
            await hooks.pause()
        }
        return await isCurrent(space)
    }

    private func isCurrent(_ space: SpaceID) async -> Bool {
        await hooks.spaces().first { $0.id == space }?.isCurrent == true
    }
}
