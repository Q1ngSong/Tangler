/// Hands Accessibility notifications from the observer thread to the event queue. A window
/// that moves sixty times a second needs one read per turn of the queue, not sixty queued
/// reads that would fall behind, so a notification already waiting is not queued again.
/// Focus changes wait once per app rather than per window: handling reads the app's focus
/// as it is then, so focus moving A→B→A cannot end up on B.
final class NotificationDispatch<Handle: Hashable>: @unchecked Sendable {
    struct Key: Hashable {
        let pid: Int32
        let notification: WindowNotification
        /// nil for focus changes.
        let element: Handle?
    }

    private let pending = PendingKeys<Key>()
    private let enqueue: (@escaping () -> Void) -> Void
    private let handle: (WindowNotification, Handle, Int32) -> Void

    /// `enqueue` runs work in order on the event queue, where `handle` then runs.
    init(enqueue: @escaping (@escaping () -> Void) -> Void,
         handle: @escaping (_ notification: WindowNotification, _ element: Handle, _ pid: Int32) -> Void) {
        self.enqueue = enqueue
        self.handle = handle
    }

    func deliver(_ notification: WindowNotification, element: Handle, pid: Int32) {
        let key = Key(pid: pid, notification: notification, element: notification == .focusChanged ? nil : element)
        guard pending.admit(key) else { return }
        enqueue { [self] in
            pending.take(key)
            handle(notification, element, pid)
        }
    }
}
