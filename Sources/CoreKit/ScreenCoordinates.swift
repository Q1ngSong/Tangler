import CoreGraphics

/// Converts between AppKit screen coordinates (origin at the bottom-left of the primary
/// display, y up) and the global coordinates every Tangler contract uses (origin at the
/// top-left of the primary display, y down, as in CoreGraphics and the Accessibility API).
/// The conversion is its own inverse, so the same call works in both directions.
public enum ScreenCoordinates {
    public static func flip(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func flip(_ point: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }
}
