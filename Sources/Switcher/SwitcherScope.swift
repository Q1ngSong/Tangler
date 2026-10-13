import Contracts

/// Which of the catalog's windows one switcher lists, and where its selection starts.
struct SwitcherScope: Equatable {
    /// Only this application's windows; nil lists every application's.
    var pid: Int32?
    /// Only windows on these Spaces, used when other Spaces cannot be listed reliably.
    /// Windows whose Spaces are unknown stay. Nil ignores Spaces.
    var spaces: Set<SpaceID>?
    var includeMinimized: Bool

    init(pid: Int32? = nil, spaces: Set<SpaceID>? = nil, includeMinimized: Bool) {
        self.pid = pid
        self.spaces = spaces
        self.includeMinimized = includeMinimized
    }

    /// The windows to list, keeping the order of `ordered` but putting minimized windows
    /// last: they were put away, so they are the least likely target.
    func windows(from ordered: [WindowInfo]) -> [WindowInfo] {
        let listed = ordered.filter { window in
            (pid == nil || window.pid == pid)
                && (includeMinimized || !window.isMinimized)
                && (spaces.map { window.spaceIDs.isEmpty || !$0.isDisjoint(with: window.spaceIDs) } ?? true)
        }
        return listed.filter { !$0.isMinimized } + listed.filter(\.isMinimized)
    }

    /// The previous window, like the system's ⌘Tab: the first window is skipped when it is
    /// the focused one. `reverse` starts from the other end, as ⇧⌘Tab does. Nil when empty.
    static func startIndex(in windows: [WindowInfo], focused: WindowID?, reverse: Bool) -> Int? {
        guard !windows.isEmpty else { return nil }
        if reverse { return windows.count - 1 }
        return windows.count > 1 && windows[0].id == focused ? 1 : 0
    }
}
