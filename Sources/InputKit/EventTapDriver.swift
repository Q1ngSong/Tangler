/// What the tap thread calls. Every callback must return quickly: macOS disables a tap whose
/// callback stalls, and all keyboard and mouse input waits on it meanwhile.
struct EventTapHandler: Sendable {
    /// Whether to read mouse moves at all; they are frequent and usually unwanted.
    var wantsMouseMoved: @Sendable () -> Bool
    /// Returns true to swallow the event.
    var handle: @Sendable (RawInputEvent) -> Bool
    /// The system disabled the tap and it was switched back on; events were missed meanwhile.
    var tapReenabled: @Sendable () -> Void
}

/// The global event tap, behind a protocol so tests drive the service with plain values.
protocol EventTapDriver: AnyObject, Sendable {
    /// Whether the tap is installed and enabled.
    var isRunning: Bool { get }
    /// Whether a tap could be created now. Filtering taps need the Accessibility permission.
    func canCreateTap() -> Bool
    /// Installs the tap and calls `handler` on the tap's own thread. False when the tap
    /// cannot be created; true when it is already running.
    func start(_ handler: EventTapHandler) -> Bool
    /// Removes the tap. Returns once no callback can run any more.
    func stop()
}
