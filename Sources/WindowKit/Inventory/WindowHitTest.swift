import Contracts
import CoreGraphics

/// Finds the window under a point among the windows the inventory manages. Everything else
/// is looked through, never returned: Tangler's own overlays (the window picker's mask sits
/// above every window), other apps' panels and the menu bar.
enum WindowHitTest {
    /// What the inventory knows about a window.
    enum Knowledge {
        /// `windows()` lists it and it is not minimized.
        case managed
        /// `windows()` lists it but it is minimized.
        case minimized
        case unknown
    }

    /// `records` run front to back. The topmost normal window the inventory has not met, such
    /// as one opened a moment ago, goes to `learn` before it is looked through; `learn` says
    /// whether it is managed after all.
    static func windowID(at point: CGPoint, in records: [WindowServerRecord], ownPID: Int32,
                         knowledge: (WindowID) -> Knowledge,
                         learn: (WindowServerRecord) async -> Bool) async -> WindowID? {
        var learned = false
        for record in records.sorted(by: { $0.order < $1.order })
        where record.pid != ownPID && record.alpha > 0 && record.frame.contains(point) {
            switch knowledge(record.id) {
            case .managed: return record.id
            case .minimized: continue
            case .unknown:
                // Each attempt scans an app, so one per lookup.
                guard !learned, record.hasManageableShape else { continue }
                learned = true
                if await learn(record) { return record.id }
            }
        }
        return nil
    }

    /// For when the window server list cannot be read: the inventory's last front-to-back order.
    static func windowID(at point: CGPoint, in windows: [WindowInfo], ownPID: Int32) -> WindowID? {
        windows.first { $0.pid != ownPID && !$0.isMinimized && $0.frame.contains(point) }?.id
    }
}
