import CoreGraphics

/// A rectangle expressed as fractions of a reference area, usually a display's visible frame.
/// Workspaces store placements this way so they survive resolution and display changes.
public struct UnitRect: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public static let full = UnitRect(x: 0, y: 0, width: 1, height: 1)

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// `frame` relative to `bounds`; `.full` when `bounds` has no area.
    public init(frame: CGRect, in bounds: CGRect) {
        guard bounds.width > 0, bounds.height > 0 else {
            self = .full
            return
        }
        self.init(x: Double((frame.minX - bounds.minX) / bounds.width),
                  y: Double((frame.minY - bounds.minY) / bounds.height),
                  width: Double(frame.width / bounds.width),
                  height: Double(frame.height / bounds.height))
    }

    public func frame(in bounds: CGRect) -> CGRect {
        CGRect(x: bounds.minX + CGFloat(x) * bounds.width, y: bounds.minY + CGFloat(y) * bounds.height,
               width: CGFloat(width) * bounds.width, height: CGFloat(height) * bounds.height)
    }
}

public enum ScreenEdge: String, Codable, Sendable {
    case top, bottom, left, right
}
