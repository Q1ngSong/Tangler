import CoreGraphics

/// One tab group as other modules see it.
public struct TabGroupSnapshot: Equatable, Sendable {
    /// Tab order, left to right.
    public var members: [WindowID]
    /// The window in front, whose tab is highlighted.
    public var active: WindowID
    /// The bar's strip plus the windows' frame below it, in global coordinates.
    public var area: CGRect
    /// The desktop the group lives on; nil when Spaces are unknown, and for a group whose window in
    /// front is shown on every desktop.
    public var spaceID: SpaceID?

    public init(members: [WindowID], active: WindowID, area: CGRect, spaceID: SpaceID? = nil) {
        self.members = members
        self.active = active
        self.area = area
        self.spaceID = spaceID
    }
}

/// Reads and makes tab groups. Implemented by TabGroups and used by Workspaces, so neither
/// feature module imports the other (workspaces design 5.4).
public protocol TabGroupService: AnyObject, Sendable {
    /// Every group as it stands between requests, never one caught while its windows are regrouped.
    func groups() async -> [TabGroupSnapshot]
    /// Makes one group of `members`, in that order, filling `area`, whose top strip becomes the
    /// bar; the service places the windows. It is for windows on the desktop that is showing, and
    /// needs two of them open there: when the window that will be in front is known to be on a
    /// desktop that is not showing, the request is refused with
    /// `.rejected("这些窗口不在当前桌面上")` and nothing is touched, because focusing that window
    /// would take the screen to its desktop. Go there first, with `WindowService.switchTo`.
    /// Minimized and full-screen windows, windows on another display
    /// or desktop than the one that will be in front, and windows that cannot take the size are
    /// left out: the group returned says who is in. A window that takes its place in the group at
    /// a size of its own no more than 24 points off, as one sized in character cells does, is in
    /// and keeps that size; the group still fills `area`. `active` becomes the tab in front, or the first
    /// member when it is not in the group, and is focused, also when the request is repeated; the
    /// group stands even if that fails. Repeating a request changes nothing but the tab in front.
    /// A window grouped elsewhere leaves that group first, which ends a group of two.
    /// A failure means no group was made: the windows moved for it are put back, but those taken
    /// out of other groups stay out of them. It is `.unsupported` when the service has stopped.
    /// An area that cannot hold the bar and a window is refused, and nothing is touched.
    func form(members: [WindowID], active: WindowID, area: CGRect) async -> Result<TabGroupSnapshot, WindowError>
}
