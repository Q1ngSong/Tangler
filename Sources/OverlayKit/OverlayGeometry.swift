import AppKit
import CoreKit

/// Converts between the global coordinates every contract uses (origin at the top-left of
/// the primary display, y down) and the AppKit screen coordinates windows are placed in.
public enum OverlayGeometry {
    /// Height of the primary display, the one with the menu bar; its AppKit origin is (0, 0).
    /// `NSScreen.main` is the screen with the key window, so it is not used here.
    @MainActor
    public static var primaryDisplayHeight: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }

    /// The pointer position in global coordinates.
    @MainActor
    public static var mouseLocation: CGPoint {
        globalPoint(fromAppKit: NSEvent.mouseLocation, primaryHeight: primaryDisplayHeight)
    }

    public static func appKitFrame(for globalFrame: CGRect, primaryHeight: CGFloat) -> CGRect {
        ScreenCoordinates.flip(globalFrame, primaryHeight: primaryHeight)
    }

    public static func globalFrame(fromAppKit frame: CGRect, primaryHeight: CGFloat) -> CGRect {
        ScreenCoordinates.flip(frame, primaryHeight: primaryHeight)
    }

    public static func globalPoint(fromAppKit point: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        ScreenCoordinates.flip(point, primaryHeight: primaryHeight)
    }

    /// `rect` relative to `canvas`, both global. Content of a panel covering `canvas` with its
    /// origin at the top-left (SwiftUI views, flipped layer views) uses this frame directly.
    public static func localFrame(of rect: CGRect, in canvas: CGRect) -> CGRect {
        rect.offsetBy(dx: -canvas.minX, dy: -canvas.minY)
    }
}
