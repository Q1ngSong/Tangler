import Foundation

/// The Dock's own settings, as the user set them in System Settings. Only ever read.
enum DockPreferences {
    private static let domain = "com.apple.dock" as CFString

    /// Whether the Dock hides until the pointer reaches its screen edge.
    static func autohides() -> Bool {
        CFPreferencesAppSynchronize(domain)
        return (CFPreferencesCopyAppValue("autohide" as CFString, domain) as? NSNumber)?.boolValue ?? false
    }
}
