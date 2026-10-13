import CoreKit
import Contracts
import CoreGraphics

/// Names a tab group for as long as Tangler runs; never reused.
struct TabGroupID: Hashable, Sendable, CustomStringConvertible {
    let rawValue: Int
    var description: String { L10n.text("tabgroups.tab.group", String(describing: (rawValue))) }
}

/// Windows sharing one area behind a tab bar (tab groups design 4.1).
struct TabGroup: Equatable, Sendable {
    let id: TabGroupID
    /// Tab order, left to right.
    var members: [WindowID]
    /// The window in front, whose tab is highlighted.
    var active: WindowID
    /// The bar's strip plus the windows' frame below it, in global coordinates.
    var area: CGRect
    var displayID: DisplayID?
    /// The Space the group lives on; nil when Spaces are unknown.
    var spaceID: SpaceID?
}
