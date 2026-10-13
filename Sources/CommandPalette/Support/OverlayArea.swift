import Contracts
import CoreGraphics

/// Where the leader hints and the palette appear: on the display showing the window they act
/// on, so they are in view while the user looks at it.
enum OverlayArea {
    /// The visible frame of the display that holds most of `windowFrame`; without one, the
    /// display under `pointer`, then the main display.
    static func visibleFrame(windowFrame: CGRect?, pointer: CGPoint, displays: [DisplayInfo]) -> CGRect? {
        if let windowFrame,
           let best = displays.max(by: { overlap($0.frame, windowFrame) < overlap($1.frame, windowFrame) }),
           overlap(best.frame, windowFrame) > 0 {
            return best.visibleFrame
        }
        if let underPointer = displays.first(where: { $0.frame.contains(pointer) }) {
            return underPointer.visibleFrame
        }
        return (displays.first(where: \.isMain) ?? displays.first)?.visibleFrame
    }

    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let shared = a.intersection(b)
        return shared.isNull ? 0 : shared.width * shared.height
    }
}

/// Looks up the area for a target window through the window service.
@MainActor
struct OverlayAreaFinder {
    let windows: any WindowService
    let pointer: () -> CGPoint

    func area(for target: WindowID?) async -> CGRect {
        var frame: CGRect?
        if let target { frame = await windows.window(target)?.frame }
        let displays = await windows.displays()
        return OverlayArea.visibleFrame(windowFrame: frame, pointer: pointer(), displays: displays) ?? .zero
    }
}
