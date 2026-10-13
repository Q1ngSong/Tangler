import AppKit
import ApplicationServices
import Contracts

/// Reads the Dock's application icons through Accessibility. Hit-testing inside the Dock's
/// own process keeps Tangler's overlays, which may sit above the Dock, out of the way.
enum DockReader {
    private static let bundleID = "com.apple.dock"

    /// The Dock's process; nil while it is not running, as for a moment when it restarts.
    static func pid() -> Int32? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first { !$0.isTerminated }?.processIdentifier
    }

    /// The Dock's icon lists put together; nil when the Dock is not running or has none.
    static func dockFrame() -> CGRect? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return nil }
        let app = AXRead.application(dock.processIdentifier)
        let lists = (AXRead.attribute(app, kAXChildrenAttribute) as? [AXUIElement] ?? []).filter {
            AXRead.string(AXRead.attribute($0, kAXRoleAttribute)) == kAXListRole
        }
        let frames = lists.compactMap { try? AXRead.frame(of: $0).get() }
        return DockGeometry.union(frames)
    }

    static func item(at point: CGPoint, displays: [DisplayInfo]) -> DockItem? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return nil }
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXRead.application(dock.processIdentifier), Float(point.x), Float(point.y),
                                               &hit) == .success, var element = hit else { return nil }
        // The hit may be a label or image inside the icon; its Dock item is a few levels up.
        for _ in 0..<4 {
            AXUIElementSetMessagingTimeout(element, AXRead.timeout)
            if AXRead.string(AXRead.attribute(element, kAXRoleAttribute)) == "AXDockItem" {
                return item(element, containing: point, displays: displays)
            }
            guard let parent = AXRead.element(AXRead.attribute(element, kAXParentAttribute)) else { return nil }
            element = parent
        }
        return nil
    }

    private static func item(_ element: AXUIElement, containing point: CGPoint, displays: [DisplayInfo]) -> DockItem? {
        let subrole = AXRead.string(AXRead.attribute(element, kAXSubroleAttribute))
        guard DockGeometry.isApplicationItem(role: "AXDockItem", subrole: subrole),
              case .success(let frame) = AXRead.frame(of: element), frame.contains(point) else { return nil }
        let bundleID = (AXRead.attribute(element, kAXURLAttribute) as? URL).flatMap { Bundle(url: $0)?.bundleIdentifier }
        let isRunning = AXRead.bool(AXRead.attribute(element, "AXIsApplicationRunning")) ?? false
        let pid = isRunning ? bundleID.flatMap { identifier in
            NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first { !$0.isTerminated }?.processIdentifier
        } : nil
        let display = DisplayLocator.display(at: CGPoint(x: frame.midX, y: frame.midY), in: displays)
        let list = AXRead.element(AXRead.attribute(element, kAXParentAttribute)).flatMap { try? AXRead.frame(of: $0).get() }
        let edge = DockGeometry.edge(listFrame: list ?? frame, displayFrame: display?.frame ?? frame)
        return DockItem(appName: AXRead.string(AXRead.attribute(element, kAXTitleAttribute)) ?? "", bundleID: bundleID,
                        pid: pid, iconFrame: frame, dockEdge: edge, displayID: display?.id)
    }
}
