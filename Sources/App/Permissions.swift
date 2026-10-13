import AppKit
import CoreGraphics

enum PrivacyPane: String {
    case accessibility = "Privacy_Accessibility"
    case screenRecording = "Privacy_ScreenCapture"

    var url: URL { URL(string: "x-apple.systempreferences:com.apple.preference.security?\(rawValue)")! }
}

/// Asking for permissions is the App's job; the modules only report whether they have them.
@MainActor
enum Permissions {
    static func open(_ pane: PrivacyPane) {
        NSWorkspace.shared.open(pane.url)
    }

    /// Shows the system prompt the first time; afterwards it only reports the state.
    @discardableResult
    static func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}
