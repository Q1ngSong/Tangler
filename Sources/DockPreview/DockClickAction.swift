import Contracts

/// What a click on the icon of the app in front does instead of the Dock's default.
enum DockClickAction: Equatable {
    case minimize(WindowID)
    case hide(pid: Int32)

    /// nil leaves the click to the Dock: an app not in front, or nothing to act on.
    /// `focused` is the focused window, needed only to minimize.
    static func forClick(on item: DockItem, behavior: DockClickBehavior, frontmostPID: Int32?,
                         focused: WindowInfo?) -> DockClickAction? {
        guard let pid = item.pid, pid == frontmostPID else { return nil }
        switch behavior {
        case .systemDefault:
            return nil
        case .minimizeWindow:
            guard let focused, focused.pid == pid, !focused.isMinimized else { return nil }
            return .minimize(focused.id)
        case .hideApplication:
            return .hide(pid: pid)
        }
    }
}
