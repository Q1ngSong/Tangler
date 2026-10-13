import CoreKit
import CoreGraphics

/// Reads and changes windows, displays and Spaces. Implemented by WindowKit, the only
/// module allowed to use the Accessibility API and SkyLight (design section 3.3).
///
/// Cancellation: an operation that has started runs to its end whether or not its task is
/// cancelled, and none refuses a task that is cancelled already, so a cancelled caller can still
/// roll back with `removeSpace`, `switchTo` and `close`. Check cancellation before calling. The one
/// operation that looks at it says so: `openNewWindow`, before it has pressed anything.
///
/// Desktop operations are exclusive: `addSpace`, `removeSpace` and the Mission Control route of
/// `switchTo` run one at a time, and a second one while another runs fails with
/// `.rejected("上一个桌面操作还没有完成")`; it is not queued. `switchTo`'s other route, focusing a
/// window, is not serialized with them, so run desktop operations one at a time.
public protocol WindowService: AnyObject, Sendable {
    var capabilities: WindowCapabilities { get }
    /// Why `capability` is unavailable and what replaces it, so greyed-out commands can say
    /// why; nil when every flag in `capability` is available.
    func unavailableReason(for capability: WindowCapabilities) -> String?
    var isAuthorized: Bool { get }
    /// Whether Mission Control, App Exposé or Show Desktop is showing, as the Dock announces it:
    /// about a quarter of a second after one comes up, and again after it goes away. Every change
    /// is followed by `.exposeChanged`. False without Accessibility permission and while the Dock
    /// is not running. One that was up before the service began to watch is not known, except
    /// Mission Control. What the Dock did not announce is not guessed: should it ever fail to say
    /// that App Exposé or Show Desktop ended, this stays true until the next one ends.
    var isExposeShowing: Bool { get }

    /// Every manageable window, including minimized ones and, when
    /// `capabilities` contains `.otherSpaceWindows`, windows on other Spaces. Every window is read
    /// for this answer, its `spaceIDs` included.
    func windows() async -> [WindowInfo]
    /// One window, read again for this answer. Like `windows()` it reports the Spaces the window
    /// is on now, not those an earlier answer or event had: a window that was moved to another
    /// desktop, or whose desktop was removed, shows its new one at once.
    func window(_ id: WindowID) async -> WindowInfo?
    func focusedWindowID() async -> WindowID?
    /// The frontmost manageable window containing `point`: only windows `windows()` lists,
    /// in front-to-back order, never minimized ones and never Tangler's own windows, because
    /// overlays such as the window picker cover whole displays.
    func windowID(at point: CGPoint) async -> WindowID?
    func displays() async -> [DisplayInfo]
    func spaces() async -> [SpaceInfo]
    func dockItem(at point: CGPoint) async -> DockItem?
    /// Where the Dock's icons are: its icon lists put together, as read while nothing hovers
    /// them. nil when the Dock is not running or cannot be read.
    func dockFrame() async -> CGRect?

    /// A new stream of changes for each caller. The service's first full scan emits nothing;
    /// read the initial list with `windows()`.
    func events() -> AsyncStream<WindowEvent>

    /// Moves and resizes a window; returns the frame read back after the change. Frames are
    /// written in whole points, so a fractional target reads back up to half a point off. When a newer
    /// call for the same window interrupts this one, both return the newest target's read-back.
    func setFrame(_ id: WindowID, to frame: CGRect, animation: FrameAnimation) async -> Result<CGRect, WindowError>
    /// Restores the window if minimized, brings it to the front and gives it keyboard focus.
    /// Only this window comes forward: the app's other windows keep their places behind other
    /// apps' windows, which tab groups rely on (tab groups design 2.1).
    func focus(_ id: WindowID) async -> Result<Void, WindowError>
    func minimize(_ id: WindowID) async -> Result<Void, WindowError>
    func close(_ id: WindowID) async -> Result<Void, WindowError>
    func move(_ id: WindowID, toSpace space: SpaceID) async -> Result<Void, WindowError>
    /// Adds an ordinary desktop at the end of `display`'s desktops, through Mission Control, which
    /// shows for about a second. With `switching` it also goes there; when only that part fails
    /// the result is still a success and the desktop's `isCurrent` is false. `isCurrent` is what
    /// the Space list says when the call returns. A display that has no desktops is refused with
    /// `.rejected("这台显示器没有桌面")` before Mission Control opens. A success is followed by
    /// `.spacesChanged`. Needs `.manageSpaces`.
    func addSpace(on display: DisplayID, switching: Bool) async -> Result<SpaceInfo, WindowError>
    /// Makes an ordinary desktop the current one. A desktop in the same row of Spaces as the one
    /// showing on its display is reached with synthetic Dock swipes, in about 50 ms a step and
    /// without the animation; the system then gives the desktop the focus it last had, and
    /// `preferred` is focused only when it is a window on that desktop that is not minimized. An
    /// empty desktop is reached this way too, without Mission Control. When the swipes cannot be
    /// used or do not land (the screen is locked, Mission Control is showing, the pointer is on
    /// another display, another desktop operation runs), the desktop is reached from wherever the
    /// screen is by focusing a window that is on it alone, and through Mission Control (which
    /// needs `.manageSpaces`) when it has none or when focusing did not go there. The window
    /// focused is then `preferred` when that is on the desktop alone and not minimized, and
    /// otherwise the first such window `windows()` lists. Which one it is matters: keyboard focus
    /// moves to it, and a tab group makes the focused window its tab in front. A desktop without
    /// such a window leaves the focus alone. Success exactly when the desktop is current at the
    /// end; on failure the focus is given back to the window that had it, and the screen may be
    /// on a Space between the two. Needs `.spaceList`: without it the answer is `.unsupported`
    /// with the reason, and nothing is tried.
    func switchTo(space: SpaceID, focusing preferred: WindowID?) async -> Result<Void, WindowError>
    /// Removes an ordinary desktop, never a display's last one; macOS moves its windows to a
    /// neighbouring desktop, and `windows()` and `window(_:)` say which when this returns. A
    /// success is followed by `.spacesChanged`. Needs `.manageSpaces`.
    func removeSpace(_ space: SpaceID) async -> Result<Void, WindowError>
    /// True only when no application window occupies this desktop, including minimized and hidden
    /// windows. Desktop elements and this service's own overlays are excluded. nil means the
    /// inventory or a window's membership could not be established; never treat nil as empty.
    func isSpaceEmpty(_ space: SpaceID) async -> Bool?
    /// Like `removeSpace`, but refuses a desktop unless it is still empty immediately before
    /// each removal request, including a retry through an expanded Mission Control bar.
    func removeSpaceIfEmpty(_ space: SpaceID) async -> Result<Void, WindowError>
    /// Whether the application's menu bar has an item that opens another window of it. nil when
    /// that could not be told: the application did not answer in time, as a busy one does not, or
    /// Accessibility permission is missing. nil is not "no": ask again later.
    func canOpenNewWindow(pid: Int32) async -> Bool?
    /// Presses that item and waits, up to 3 seconds, for the application to have a window it did
    /// not have before, then up to 2 more for this service to know it; returns that window, which
    /// `window(_:)`, `setFrame` and `focus` accept at once. The window is expected on the current
    /// desktop. The application is not asked to come to the front, but it may (Finder does).
    /// Once the item is pressed the call runs to its end, also in a task cancelled meanwhile, so
    /// the window that comes is always handed to someone: a caller that no longer wants it closes
    /// it. It fails with
    /// - `.notAuthorized` without Accessibility permission;
    /// - `.unsupported` when the menu bar has no such item;
    /// - `.appNotResponding` when the menus could not be read;
    /// - `.rejected("这个应用的上一个新窗口还没有开出来")` while an earlier call for the same
    ///   application is still running: one application opens one window at a time, because two
    ///   windows opening together cannot be told apart;
    /// - `.rejected("已取消")` when the task was cancelled before the press: nothing was pressed;
    /// - `.rejected("没能点到“新建窗口”")` when the item could not be pressed;
    /// - `.rejected("应用没有开出新窗口")` when no new window came in time;
    /// - `.rejected("新窗口没有出现在窗口清单里")` when the new window never became known to this
    ///   service, as a helper window does not.
    func openNewWindow(pid: Int32) async -> Result<WindowID, WindowError>
    func hideApplication(pid: Int32) async -> Result<Void, WindowError>
}

public extension WindowService {
    func isSpaceEmpty(_ space: SpaceID) async -> Bool? { nil }
    func removeSpaceIfEmpty(_ space: SpaceID) async -> Result<Void, WindowError> {
        .failure(.unsupported(L10n.text("contracts.empty.desktops.cannot.be.cleaned.up.safely")))
    }
}
