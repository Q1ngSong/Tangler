import Contracts

/// Which windows sit on a desktop, from the window server's list and its Space membership. As
/// everywhere in WindowKit, nil membership means it could not be read and an empty one means the
/// window is on no Space.
enum SpaceOccupancy {
    /// Ordinary windows that are on `space` and on no other; nil when a window's Spaces cannot be
    /// read. A window shown on every desktop, such as an overlay, occupies none of them, and
    /// neither does a window the window server reports on no Space, as a hidden application's may be.
    static func count(on space: SpaceID, records: [WindowServerRecord], spaceIDs: (WindowID) -> [SpaceID]?) -> Int? {
        var count = 0
        for record in records where record.layer == 0 {
            guard let spaces = spaceIDs(record.id) else { return nil }
            if spaces == [space] { count += 1 }
        }
        return count
    }

    /// Cleanup is stricter than temporary-desktop occupancy: a window on several desktops
    /// protects all of them. Managed windows supplement the server list, which may omit minimized
    /// windows. A hidden app's unassigned records are ambiguous, not proof of an empty desktop.
    static func isEmpty(on space: SpaceID, records: [WindowServerRecord], windows: [WindowInfo],
                        hiddenPIDs: Set<Int32>, ownPID: Int32,
                        spaceIDs: (WindowID) -> [SpaceID]?) -> Bool? {
        var unknown = false
        for window in windows {
            guard let membership = spaceIDs(window.id), !membership.isEmpty else { unknown = true; continue }
            if membership.contains(space) { return false }
        }
        for record in records where record.layer == 0 && record.pid != ownPID {
            guard let membership = spaceIDs(record.id) else { unknown = true; continue }
            if membership.contains(space) { return false }
            if membership.isEmpty && (hiddenPIDs.contains(record.pid) || record.isOnScreen) { unknown = true }
        }
        return unknown ? nil : true
    }

    /// Whether a window server entry is an open ordinary window. Closed windows and hidden helper
    /// windows stay in the window server's list on no Space (workspaces design 2.5 item 8); the
    /// rule is `UnlistedWindows`', so a hidden application's windows count. When Spaces cannot be
    /// read, being on screen has to do, and a hidden application's windows, none of which is on
    /// screen, count all the same. For a hidden application this is true of every ordinary entry
    /// it has, closed and helper windows included, so compare window numbers before and after
    /// rather than counting.
    static func isOpen(_ record: WindowServerRecord, appIsHidden: Bool, spaceIDs: [SpaceID]?) -> Bool {
        guard record.layer == 0 else { return false }
        return UnlistedWindows.isOpen(appIsHidden: appIsHidden, spaceIDs: spaceIDs) ?? (appIsHidden || record.isOnScreen)
    }
}
