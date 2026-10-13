import Contracts
import CoreGraphics

/// One tab in a bar.
struct TabItem: Equatable, Identifiable, Sendable {
    var id: WindowID
    var title: String
    var appName: String
    var pid: Int32
    var bundleID: String?
    var isActive: Bool
    /// Its app is hidden; the tab is drawn faded.
    var isHidden: Bool

    /// The title, or the app's name for a window without one.
    var label: String { title.isEmpty ? appName : title }
}

/// The tab a drag would put in a bar, and the slot it would take.
struct IncomingTab: Equatable, Sendable {
    var tab: TabItem
    /// Among the bar's slots with this tab counted: 0 is the leftmost.
    var slot: Int
}

/// What a bar shows.
struct TabBarContent: Equatable, Sendable {
    var group: TabGroupID
    var tabs: [TabItem]
    /// The tab a drag would put here, or one of `tabs` on its way to another slot; nil when
    /// nothing hovers.
    var incoming: IncomingTab?
    /// One of `tabs` being dragged away from this bar; it is drawn faded.
    var leaving: WindowID?
}

/// What the bars' controls ask for; the controller carries it out.
enum TabBarAction: Equatable, Sendable {
    case select(WindowID)
    /// × or the context menu: close the window, as its own close button would.
    case close(WindowID)
    case remove(WindowID)
    case ungroup(TabGroupID)
    /// A tab dragged to a point, in global coordinates, `command` while ⌘ alone is held…
    case drag(WindowID, CGPoint, command: Bool)
    /// …and where it was let go.
    case drop(WindowID, CGPoint, command: Bool)
}

/// Puts the bars on screen. The real one keeps one overlay panel per group; tests use a recorder.
@MainActor
protocol TabBarPresenting: AnyObject {
    /// Whether bars can sit just above their window, which takes the window server's window
    /// numbers; otherwise they float above every window.
    var ordersAboveWindow: Bool { get set }
    /// Shows `content.group`'s bar filling `frame` (global). A bar that is not up yet comes on screen
    /// on the Space showing now, just above `window`, and belongs to that Space from then on. One
    /// already up only takes the new content and frame, and keeps its place until `reorder`.
    func show(_ content: TabBarContent, frame: CGRect, above window: WindowID,
              onAction: @escaping @MainActor (TabBarAction) -> Void)
    /// New content and frame for a bar that is up; nothing when none is. For a group whose Space is
    /// not showing: putting a bar up now would put it on the wrong Space.
    func update(_ content: TabBarContent, frame: CGRect)
    /// Puts the bar back just above `window`, e.g. after the window was raised over it.
    func reorder(_ group: TabGroupID, above window: WindowID)
    /// Brings the bar in front of every window at its level, e.g. above a window dragged over
    /// it; `reorder` puts it back. Only for a bar whose Space is showing.
    func lift(_ group: TabGroupID)
    func hide(_ group: TabGroupID)
    func hideAll()
    /// Makes every bar invisible and deaf to the mouse, or brings them all back, while they stay
    /// up where they are: for Mission Control, App Exposé and Show Desktop, which leave the bars
    /// drawn in place. Nothing else changes meanwhile: bars still take content and frames, and one
    /// put up while hidden starts hidden.
    func setHidden(_ hidden: Bool)
    /// The small tab following the pointer while a tab is dragged outside the bars; nil hides it.
    func showGhost(_ tab: TabItem?, at point: CGPoint)
}
