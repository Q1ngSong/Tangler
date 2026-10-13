import CoreKit
import Contracts
import Foundation

/// Opens another window of an application by pressing its own menu item (workspaces design 5.2,
/// 7.5). The new window is the one the application did not have before the press, so one
/// application opens one window at a time: two presses that overlap could not tell their windows
/// apart. A window is handed back only once the service knows it, so that it can be moved,
/// focused and read at once. Cancellation is looked at once, just before the press; after a press
/// that was sent the flow runs to its end, so that the window that comes always has someone who
/// is told of it: one nobody tracked would pass for the next call's new window.
final class NewWindowOpener: @unchecked Sendable {
    struct Hooks {
        /// The application's menu items, as far as they are read; nil when they could not be read,
        /// which does not say the application has no such item.
        var items: (Int32) async -> [AppMenuItem]?
        /// Presses an item. False means only that it was not found and nothing was sent; true does
        /// not say a window came.
        var press: (AppMenuItem, Int32) async -> Bool
        /// The application's open ordinary windows.
        var windows: (Int32) -> Set<WindowID>
        /// Waits between checks for the window. It has to wait even when the task is cancelled:
        /// the item is pressed by then, and the window that comes has to be handed back.
        var pause: () async -> Void
        /// Whether the service's window list has the window.
        var isKnown: (WindowID) async -> Bool
        /// Waits between checks of the window list. It has to wait even when the task is
        /// cancelled: the window is open by then, and the caller is told which one it is.
        var settle: () async -> Void
    }

    private let pollLimit: Int
    private let knownLimit: Int
    private let hooks: Hooks
    private let opening = Locked<Set<Int32>>([])

    /// Gives up on the window after `pollLimit` pauses, 3 seconds with the live 40 ms pause, and
    /// on the window list after `knownLimit` more waits, 2 seconds with the live 100 ms.
    init(pollLimit: Int = 75, knownLimit: Int = 20, hooks: Hooks) {
        self.pollLimit = pollLimit
        self.knownLimit = knownLimit
        self.hooks = hooks
    }

    /// nil when the application's menus could not be read.
    func canOpen(pid: Int32) async -> Bool? {
        guard let items = await hooks.items(pid) else { return nil }
        return NewWindowMenu.choose(from: items) != nil
    }

    func open(pid: Int32) async -> Result<WindowID, WindowError> {
        guard opening.update({ $0.insert(pid).inserted }) else {
            return .failure(.rejected(L10n.text("windowkit.this.app.s.previous.new.window.has")))
        }
        defer { opening.update { $0.remove(pid) } }

        guard let items = await hooks.items(pid) else { return .failure(.appNotResponding(pid: pid)) }
        guard let item = NewWindowMenu.choose(from: items) else {
            return .failure(.unsupported(L10n.text("windowkit.this.app.has.no.new.window.menu")))
        }
        // Reading the menus can take seconds; nobody may be waiting for the window any more.
        // The one place that looks at cancellation: past the press the flow runs to its end.
        guard !Task.isCancelled else { return .failure(.rejected(L10n.text("windowkit.cancelled"))) }
        let before = hooks.windows(pid)
        guard await hooks.press(item, pid) else { return .failure(.rejected(L10n.text("windowkit.could.not.click.new.window"))) }
        for _ in 0..<pollLimit {
            await hooks.pause()
            // Several at once: the one with the lowest number.
            if let fresh = hooks.windows(pid).subtracting(before).min() { return await known(fresh) }
        }
        return .failure(.rejected(L10n.text("windowkit.the.app.did.not.open.a.new")))
    }

    /// The window server lists a window before the application answers for it, and lists helper
    /// windows Accessibility never does.
    private func known(_ id: WindowID) async -> Result<WindowID, WindowError> {
        for _ in 0..<knownLimit {
            if await hooks.isKnown(id) { return .success(id) }
            await hooks.settle()
        }
        return await hooks.isKnown(id) ? .success(id) : .failure(.rejected(L10n.text("windowkit.the.new.window.did.not.appear.in")))
    }
}
