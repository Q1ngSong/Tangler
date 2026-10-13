import Contracts
import CoreGraphics

enum DockGeometry {
    /// The frames put together; nil when there are none or all are empty.
    static func union(_ frames: [CGRect]) -> CGRect? {
        let area = frames.filter { !$0.isEmpty }.reduce(CGRect.null) { $0.union($1) }
        return area.isNull ? nil : area
    }

    /// The display edge the Dock occupies, from the frame of its icon list. The Dock is never
    /// at the top, and its list is always wider than tall at the bottom, taller than wide on a side.
    static func edge(listFrame: CGRect, displayFrame: CGRect) -> ScreenEdge {
        if listFrame.width >= listFrame.height { return .bottom }
        return listFrame.midX < displayFrame.midX ? .left : .right
    }

    /// Application icons only: folders, the Trash, separators and minimized windows are not apps.
    static func isApplicationItem(role: String?, subrole: String?) -> Bool {
        role == "AXDockItem" && subrole == "AXApplicationDockItem"
    }
}
