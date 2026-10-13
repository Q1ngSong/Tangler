import Contracts
import CoreGraphics
import OverlayKit

/// Where the Dock can be and where its preview goes, in global coordinates.
enum DockPreviewGeometry {
    /// How far into a display the Dock's icons can reach from its bottom, left or right edge,
    /// magnified icons included. Pointer positions farther in never need a Dock lookup.
    static let dockReach: CGFloat = 160
    static let gap: CGFloat = 12

    /// Whether `point` is near enough to an edge of its display to be over the Dock. Before the
    /// displays are known every point qualifies, so hovering still works.
    static func mayBeOverDock(_ point: CGPoint, displays: [DisplayInfo]) -> Bool {
        guard !displays.isEmpty else { return true }
        guard let frame = displays.first(where: { $0.frame.contains(point) })?.frame else { return false }
        return point.y >= frame.maxY - dockReach || point.x <= frame.minX + dockReach
            || point.x >= frame.maxX - dockReach
    }

    /// The preview opens away from the Dock: above a bottom Dock, beside a side Dock.
    static func previewSide(for dockEdge: ScreenEdge) -> ScreenEdge {
        switch dockEdge {
        case .bottom: return .top
        case .left: return .right
        case .right: return .left
        case .top: return .bottom
        }
    }

    /// The visible area the preview stays inside: the icon's display as reported, else the
    /// display holding the icon, else the main display.
    static func area(for item: DockItem, displays: [DisplayInfo]) -> CGRect? {
        let center = CGPoint(x: item.iconFrame.midX, y: item.iconFrame.midY)
        let display = displays.first { item.displayID != nil && $0.id == item.displayID }
            ?? displays.first { $0.frame.contains(center) }
            ?? displays.first(where: \.isMain) ?? displays.first
        return display?.visibleFrame
    }

    static func placement(for item: DockItem, in area: CGRect) -> OverlayPlacement {
        .beside(item.iconFrame, side: previewSide(for: item.dockEdge), gap: gap, within: area)
    }
}
