import CoreGraphics

/// Whether this login session is locked, switched out, or unknown: its screen is locked, fast
/// user switching took it off the console, or the session dictionary could not be read at all.
/// The locked key is undocumented and absent while the screen is unlocked.
enum ScreenLock {
    static func isLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return true }
        return session["CGSSessionScreenIsLocked"] as? Bool == true || session[kCGSessionOnConsoleKey as String] as? Bool == false
    }
}
