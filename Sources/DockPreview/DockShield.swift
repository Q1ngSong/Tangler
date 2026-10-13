import Contracts
import CoreGraphics

/// Where pointer moves are kept from the Dock when its own hover is hidden: its icons with a
/// margin, out to the display edge it sits on, so no move on or beside an icon reaches it.
enum DockShield {
    /// Tried on a right-side Dock (2026-10-09): with this margin the Dock showed no names.
    static let margin: CGFloat = 8

    static func region(dock: CGRect, displays: [DisplayInfo]) -> CGRect {
        var region = dock.insetBy(dx: -margin, dy: -margin)
        let center = CGPoint(x: dock.midX, y: dock.midY)
        guard let display = displays.first(where: { $0.frame.contains(center) })?.frame else { return region }
        // The Dock is never at the top: its edge is the nearest of the other three.
        let left = dock.minX - display.minX
        let right = display.maxX - dock.maxX
        let bottom = display.maxY - dock.maxY
        if bottom <= min(left, right) {
            region.size.height = display.maxY - region.minY
        } else if right <= left {
            region.size.width = display.maxX - region.minX
        } else {
            region.size.width = region.maxX - display.minX
            region.origin.x = display.minX
        }
        return region
    }
}
