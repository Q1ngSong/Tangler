import Contracts
import CoreGraphics
import Foundation

/// A left-button press that may turn out to be a click on a Dock icon. The Dock treats long
/// presses as a request for its menu and larger movements as dragging the icon.
struct DockClickGesture {
    static let longestClick: TimeInterval = 0.5
    static let slop: CGFloat = 4
    /// How long after the release the click behaviour acts. The Dock handles the release itself,
    /// and acting first would let it undo the action, e.g. unhide the app just hidden.
    static let settleDelay: TimeInterval = 0.2

    let start: CGPoint
    let time: TimeInterval
    private(set) var wandered = false

    init(start: CGPoint, time: TimeInterval) {
        self.start = start
        self.time = time
    }

    /// Modifier clicks keep their Dock meaning, e.g. ⌘-click shows the app in Finder.
    static func isPlainLeftClick(_ event: MouseEvent) -> Bool {
        event.button == .left && event.modifiers.subtracting(.function).isEmpty
    }

    mutating func dragged(to point: CGPoint) {
        if hypot(point.x - start.x, point.y - start.y) > Self.slop { wandered = true }
    }

    func isClick(on iconFrame: CGRect, releasedAt point: CGPoint, time releaseTime: TimeInterval) -> Bool {
        !wandered && iconFrame.contains(start) && iconFrame.contains(point) && releaseTime - time <= Self.longestClick
    }
}
