import Contracts
import CoreGraphics

extension AXWindowSnapshot {
    /// The contract's view of this read.
    func info(id: WindowID, frame: CGRect, app: AppSnapshot, displays: [DisplayInfo], spaceIDs: [SpaceID]) -> WindowInfo {
        WindowInfo(id: id, pid: app.pid, bundleID: app.bundleID, appName: app.name, title: title, frame: frame,
                   displayID: DisplayLocator.display(for: frame, in: displays), spaceIDs: spaceIDs,
                   isMinimized: isMinimized, isFullscreen: isFullscreen, documentURL: documentURL)
    }

    /// The legacy minimum: anything at most 40×24 points is a helper, not a window.
    static func hasManageableSize(_ frame: CGRect) -> Bool { frame.width > 40 && frame.height > 24 }
}
