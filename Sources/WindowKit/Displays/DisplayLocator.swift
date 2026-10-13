import Contracts
import CoreGraphics

enum DisplayLocator {
    /// The display covering most of `frame`; for a window off every display, the nearest one.
    static func display(for frame: CGRect, in displays: [DisplayInfo]) -> DisplayID? {
        let covered = displays
            .map { (display: $0, area: area($0.frame.intersection(frame))) }
            .max { $0.area < $1.area }
        if let covered, covered.area > 0 { return covered.display.id }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return displays.min { distance(from: center, to: $0.frame) < distance(from: center, to: $1.frame) }?.id
    }

    static func display(at point: CGPoint, in displays: [DisplayInfo]) -> DisplayInfo? {
        displays.first { $0.frame.contains(point) }
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull || rect.isEmpty ? 0 : rect.width * rect.height
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
