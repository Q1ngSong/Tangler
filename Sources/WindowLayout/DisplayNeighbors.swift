import Contracts
import CoreGraphics
import CoreKit

enum Direction: Equatable, Sendable {
    case left, right, up, down
}

/// The display next to another one, for "移到左侧显示器" and the like.
enum DisplayNeighbors {
    /// Arrangements are in whole points; this much apart still counts as touching.
    private static let tolerance: CGFloat = 1

    /// The closest display on `direction`'s side of `source`: of those whose center lies mainly
    /// in `direction` if there are any, so an offset arrangement still has a neighbour. A display
    /// reaching that side only partly, like a taller one to the right for "down", is on another side.
    static func neighbor(of source: DisplayInfo, toward direction: Direction,
                         among displays: [DisplayInfo]) -> DisplayInfo? {
        let onSide = displays
            .filter { $0.id != source.id && lies(toward: direction, of: source.frame, $0.frame) }
            .map { (display: $0, offset: offset(from: source.frame, to: $0.frame, toward: direction)) }
            .filter { $0.offset.along > 0 }
        let mainly = onSide.filter { $0.offset.along >= abs($0.offset.across) }
        let score = { (offset: (along: CGFloat, across: CGFloat)) in offset.along + 2 * abs(offset.across) }
        return (mainly.isEmpty ? onSide : mainly).min { score($0.offset) < score($1.offset) }?.display
    }

    /// `frame` moved from one visible frame to another, keeping its position and size relative
    /// to them, then kept inside the target.
    static func transfer(_ frame: CGRect, from source: CGRect, to target: CGRect) -> CGRect {
        let relative = UnitRect(frame: frame, in: source).frame(in: target)
        return LayoutGeometry.rounded(RectMath.clamp(relative, to: target))
    }

    /// Whether `other` is wholly past `source`'s edge in `direction`, or beside that edge,
    /// sharing part of the other axis.
    private static func lies(toward direction: Direction, of source: CGRect, _ other: CGRect) -> Bool {
        let pastEdge: Bool
        let shared: CGFloat
        switch direction {
        case .left, .right:
            pastEdge = direction == .left ? other.maxX <= source.minX + tolerance : other.minX >= source.maxX - tolerance
            shared = min(other.maxY, source.maxY) - max(other.minY, source.minY)
        case .up, .down:
            pastEdge = direction == .up ? other.maxY <= source.minY + tolerance : other.minY >= source.maxY - tolerance
            shared = min(other.maxX, source.maxX) - max(other.minX, source.minX)
        }
        return pastEdge || shared > tolerance
    }

    /// Center to center, measured along `direction` and across it.
    private static func offset(from source: CGRect, to other: CGRect,
                               toward direction: Direction) -> (along: CGFloat, across: CGFloat) {
        let dx = other.midX - source.midX
        let dy = other.midY - source.midY
        switch direction {
        case .left: return (-dx, dy)
        case .right: return (dx, dy)
        case .up: return (-dy, dx)
        case .down: return (dy, dx)
        }
    }
}
