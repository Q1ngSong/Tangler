import CoreGraphics

/// Swallows key presses while alive; the newest capture receives them. A capture also ends
/// by itself when nobody consumes `keys` any more, so the keyboard is never left swallowed.
public protocol KeyCapture: AnyObject, Sendable {
    var keys: AsyncStream<KeyPress> { get }
    func end()
}

public enum InputError: Error, Equatable, Sendable {
    case notAuthorized
    case shortcutInUse(id: String)
}

/// Global keyboard and mouse input. Implemented by InputKit, the only module allowed
/// to install event taps (design section 3.3).
public protocol InputService: AnyObject, Sendable {
    var isAuthorized: Bool { get }

    /// A new stream for each caller, containing only the kinds in `filter`.
    func events(_ filter: InputEventFilter) -> AsyncStream<InputEvent>

    /// nil turns the leader off.
    func setLeaderTrigger(_ trigger: LeaderTrigger?)

    /// Whether the `.holdRightCommand` key is down, as the event tap last saw it. The system's
    /// own modifier state lags the tap, so leader mode asks here, after subscribing to modifier
    /// changes: a release is then either seen here or delivered as an event.
    var isLeaderKeyHeld: Bool { get }

    /// Accepted even without permission (it takes effect once the event tap exists).
    /// Throws only `InputError.shortcutInUse`, when another id already owns the chord.
    /// The command registry registers every `CommandSpec.globalShortcut`; feature modules don't,
    /// except for keys that are no command of their own, such as the layout module's desktop keys.
    func registerShortcut(_ chord: KeyChord, id: String) throws
    func unregisterShortcut(id: String)

    /// While suspended, global shortcuts and the leader trigger are ignored and their keys reach
    /// the frontmost app, e.g. while a settings page records a chord. Captures, mouse and
    /// modifier events are unaffected.
    func setShortcutsSuspended(_ suspended: Bool)

    /// Starts swallowing keys until the capture ends; used by leader mode and the switcher.
    func beginKeyCapture() -> any KeyCapture

    /// Pointer moves inside `region` (global, top-left origin) still reach Tangler's subscribers
    /// but no app, so the Dock never sees the pointer rest on its icons: no name label and no
    /// magnification. nil lifts it. Clicks, drags and scrolls always reach apps.
    func setMouseMoveShield(_ region: CGRect?)

    /// Turns the system Command-Tab switcher off or back on. Returns false when unavailable.
    @discardableResult
    func setSystemSwitcherSuppressed(_ suppressed: Bool) -> Bool
}
