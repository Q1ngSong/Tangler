import AppKit
import CoreGraphics

/// Reads `NSScreen`, which belongs to the main thread.
enum ScreenReader {
    @MainActor
    static func snapshots() -> [ScreenSnapshot] {
        NSScreen.screens.map { screen in
            let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            return ScreenSnapshot(displayNumber: number, uuid: uuid(of: number), name: screen.localizedName,
                                  frame: screen.frame, visibleFrame: screen.visibleFrame)
        }
    }

    /// Stays the same when the display is unplugged and plugged in again.
    static func uuid(of display: UInt32) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }
}
