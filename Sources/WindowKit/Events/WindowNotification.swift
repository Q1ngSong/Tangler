import ApplicationServices

/// What an Accessibility notification means for the inventory.
enum WindowNotification: Equatable {
    /// The element is a new window.
    case created
    /// Something about the window changed; read it again.
    case changed
    /// The element is gone; only its handle identifies the window.
    case destroyed
    /// The element is the application's newly focused window.
    case focusChanged

    /// Registered on each application element.
    static let applicationNotifications = [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification]
    /// Registered on each window element.
    static let windowNotifications = [kAXMovedNotification, kAXResizedNotification, kAXWindowMiniaturizedNotification,
                                      kAXWindowDeminiaturizedNotification, kAXTitleChangedNotification,
                                      kAXUIElementDestroyedNotification]

    init?(name: String) {
        switch name {
        case kAXWindowCreatedNotification: self = .created
        case kAXUIElementDestroyedNotification: self = .destroyed
        case kAXFocusedWindowChangedNotification: self = .focusChanged
        case kAXMovedNotification, kAXResizedNotification, kAXWindowMiniaturizedNotification,
             kAXWindowDeminiaturizedNotification, kAXTitleChangedNotification:
            self = .changed
        default: return nil
        }
    }
}
