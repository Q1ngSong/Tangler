import Contracts
import CoreGraphics
import CoreKit

/// Edge snapping on the sides of a display that end the desktop. Where another display adjoins
/// a side, the pointer goes on across rather than meeting an edge, so that stretch never snaps:
/// a window carried to the next display must not flash a preview or snap when dropped just
/// across.
enum OuterEdges {
    /// How close to an edge the pointer has to come.
    static let reach: CGFloat = 24
    /// Arrangements are in whole points; this much apart still counts as touching.
    private static let tolerance: CGFloat = 1

    private enum Side {
        case left, right, top, bottom
    }

    /// The edge target for a pointer at `point`, inside `display`'s whole frame.
    static func target(at point: CGPoint, on display: DisplayInfo, among displays: [DisplayInfo]) -> EdgeSnap? {
        let frame = display.frame
        let others = displays.filter { $0.id != display.id }.map(\.frame)
        func shared(_ side: Side) -> Bool { others.contains { adjoins($0, side, of: frame, at: point) } }
        // A shared side is taken out of reach, so EdgeSnap sees only the outer ones; a corner
        // with one shared side is just the edge of the other.
        var probe = point
        if (point.x <= frame.minX + reach && shared(.left)) || (point.x >= frame.maxX - reach && shared(.right)) {
            probe.x = frame.midX
        }
        if (point.y <= frame.minY + reach && shared(.top)) || (point.y >= frame.maxY - reach && shared(.bottom)) {
            probe.y = frame.midY
        }
        return EdgeSnap.target(for: probe, in: frame, threshold: reach)
    }

    /// Whether `other` touches `side` of `frame` level with `point`.
    private static func adjoins(_ other: CGRect, _ side: Side, of frame: CGRect, at point: CGPoint) -> Bool {
        switch side {
        case .left: return abs(other.maxX - frame.minX) <= tolerance && other.minY <= point.y && point.y < other.maxY
        case .right: return abs(other.minX - frame.maxX) <= tolerance && other.minY <= point.y && point.y < other.maxY
        case .top: return abs(other.maxY - frame.minY) <= tolerance && other.minX <= point.x && point.x < other.maxX
        case .bottom: return abs(other.minY - frame.maxY) <= tolerance && other.minX <= point.x && point.x < other.maxX
        }
    }
}
