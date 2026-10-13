import AppKit

/// Forwards AppKit's application, Space and display notifications to one queue.
final class WorkspaceMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    func start(queue: DispatchQueue, handler: @escaping (WorkspaceChange) -> Void) {
        let observe = { (center: NotificationCenter, name: Notification.Name) -> (NotificationCenter, NSObjectProtocol) in
            (center, center.addObserver(forName: name, object: nil, queue: nil) { notification in
                guard let change = WorkspaceChange(notification) else { return }
                queue.async { handler(change) }
            })
        }
        let workspace = NSWorkspace.shared.notificationCenter
        let added = WorkspaceChange.workspaceNames.map { observe(workspace, $0) }
            + WorkspaceChange.defaultCenterNames.map { observe(NotificationCenter.default, $0) }
        lock.lock()
        tokens += added.map { (center: $0.0, token: $0.1) }
        lock.unlock()
    }

    func stop() {
        lock.lock()
        let removed = tokens
        tokens.removeAll()
        lock.unlock()
        for entry in removed { entry.center.removeObserver(entry.token) }
    }
}
