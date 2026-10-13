import Contracts
import CoreGraphics

/// Finds displays for windows and points; all frames are global.
enum DisplayLookup {
    /// The display WindowKit reported for the window, else the one covering most of it,
    /// else the nearest one.
    static func display(for window: WindowInfo, in displays: [DisplayInfo]) -> DisplayInfo? {
        if let id = window.displayID, let reported = displays.first(where: { $0.id == id }) { return reported }
        let covering = displays.map { (display: $0, area: area($0.frame.intersection(window.frame))) }
            .max { $0.area < $1.area }
        if let covering, covering.area > 0 { return covering.display }
        return nearest(to: CGPoint(x: window.frame.midX, y: window.frame.midY), in: displays)
    }

    /// The display under `point`, or the nearest one when the point is outside every display.
    static func display(at point: CGPoint, in displays: [DisplayInfo]) -> DisplayInfo? {
        displays.first { $0.frame.contains(point) } ?? nearest(to: point, in: displays)
    }

    /// The display with the menu bar, which also takes windows whose display is gone.
    static func main(in displays: [DisplayInfo]) -> DisplayInfo? {
        displays.first(where: \.isMain) ?? displays.first
    }

    private static func nearest(to point: CGPoint, in displays: [DisplayInfo]) -> DisplayInfo? {
        displays.min { distance(from: point, to: $0.frame) < distance(from: point, to: $1.frame) }
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull || rect.isEmpty ? 0 : rect.width * rect.height
    }
}
