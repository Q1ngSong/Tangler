import Contracts
import CoreGraphics

/// How the preview moves as it appears: out of the Dock's side, a short way.
enum DockPreviewMotion {
    /// Where the preview starts, `distance` closer to the Dock than `final` (global, top-left origin).
    static func startFrame(for final: CGRect, dockEdge: ScreenEdge, distance: CGFloat) -> CGRect {
        switch dockEdge {
        case .right: return final.offsetBy(dx: distance, dy: 0)
        case .left: return final.offsetBy(dx: -distance, dy: 0)
        case .bottom: return final.offsetBy(dx: 0, dy: distance)
        case .top: return final.offsetBy(dx: 0, dy: -distance)
        }
    }
}
