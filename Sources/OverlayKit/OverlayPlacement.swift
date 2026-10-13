import Contracts
import CoreGraphics
import CoreKit
import Foundation

/// Where an overlay sized to its content goes, in global coordinates.
public enum OverlayPlacement: Equatable, Sendable {
    /// Centered in an area, usually a display's visible frame.
    case centered(in: CGRect)
    /// On `side` of `anchor`, `gap` points away, centered along the anchor and kept inside
    /// `within`; e.g. above a Dock icon when the Dock is at the bottom.
    case beside(CGRect, side: ScreenEdge, gap: CGFloat, within: CGRect)

    /// The area the overlay stays inside.
    public var bounds: CGRect {
        switch self {
        case .centered(let area): return area
        case .beside(_, _, _, let area): return area
        }
    }

    /// The frame for content of `size`; the size is rounded up to whole points and
    /// shrunk to fit `bounds`, the origin rounded to whole points.
    public func frame(for size: CGSize) -> CGRect {
        let width = min(ceil(size.width), bounds.width)
        let height = min(ceil(size.height), bounds.height)
        let origin: CGPoint
        switch self {
        case .centered(let area):
            origin = CGPoint(x: area.midX - width / 2, y: area.midY - height / 2)
        case .beside(let anchor, let side, let gap, _):
            switch side {
            case .top: origin = CGPoint(x: anchor.midX - width / 2, y: anchor.minY - gap - height)
            case .bottom: origin = CGPoint(x: anchor.midX - width / 2, y: anchor.maxY + gap)
            case .left: origin = CGPoint(x: anchor.minX - gap - width, y: anchor.midY - height / 2)
            case .right: origin = CGPoint(x: anchor.maxX + gap, y: anchor.midY - height / 2)
            }
        }
        let rect = CGRect(x: origin.x.rounded(), y: origin.y.rounded(), width: width, height: height)
        return RectMath.clamp(rect, to: bounds)
    }
}
