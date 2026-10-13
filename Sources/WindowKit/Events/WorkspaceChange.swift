import AppKit

/// Application, Space and display changes announced by AppKit.
enum WorkspaceChange: Equatable {
    case launched(Int32)
    case terminated(Int32)
    case hidden(Int32)
    case unhidden(Int32)
    case activated(Int32)
    case activeSpaceChanged
    case displaysChanged
    case woke

    /// Posted on `NSWorkspace.shared.notificationCenter`.
    static let workspaceNames: [Notification.Name] = [
        NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
        NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification,
        NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
        NSWorkspace.didWakeNotification,
    ]
    /// Posted on `NotificationCenter.default`.
    static let defaultCenterNames: [Notification.Name] = [NSApplication.didChangeScreenParametersNotification]

    init?(_ notification: Notification) {
        let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
        switch notification.name {
        case NSWorkspace.activeSpaceDidChangeNotification: self = .activeSpaceChanged
        case NSWorkspace.didWakeNotification: self = .woke
        case NSApplication.didChangeScreenParametersNotification: self = .displaysChanged
        case NSWorkspace.didLaunchApplicationNotification: guard let pid else { return nil }; self = .launched(pid)
        case NSWorkspace.didTerminateApplicationNotification: guard let pid else { return nil }; self = .terminated(pid)
        case NSWorkspace.didHideApplicationNotification: guard let pid else { return nil }; self = .hidden(pid)
        case NSWorkspace.didUnhideApplicationNotification: guard let pid else { return nil }; self = .unhidden(pid)
        case NSWorkspace.didActivateApplicationNotification: guard let pid else { return nil }; self = .activated(pid)
        default: return nil
        }
    }
}
