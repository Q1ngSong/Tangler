import Contracts
import CoreGraphics
import Foundation

/// One block of the preview: an entry, or a tab group with its tabs.
struct PreviewTile: Equatable, Identifiable {
    /// The entry shown large; a group's tab in front.
    var active: UUID
    /// The entries in tab order; one for an entry outside any group.
    var tabs: [UUID]
    /// On the board, origin at the top left.
    var rect: CGRect
    var showsTabBar: Bool
    /// The entry focused after expanding is in this tile.
    var isFocused: Bool

    var id: UUID { tabs.first ?? active }
}

/// Where a checkpoint's entries go on the preview's board (workspaces design, section 8).
/// Only saved data is used: no screenshots and no screen recording permission.
enum PreviewLayout {
    static let minimumSide: CGFloat = 10
    /// How far a tile steps right and down from an earlier one saved at the same place.
    static let cascadeStep: CGFloat = 6

    /// The largest board of the saved aspect that fits `room`.
    static func boardSize(aspect: Double?, fallback: Double, in room: CGSize) -> CGSize {
        let usable = { (value: Double?) in value.flatMap { $0.isFinite && $0 > 0 ? CGFloat($0) : nil } }
        let ratio = usable(aspect) ?? usable(fallback) ?? 1.6
        guard room.width > 0, room.height > 0 else { return .zero }
        let height = min(room.height, room.width / ratio)
        return CGSize(width: (height * ratio).rounded(), height: height.rounded())
    }

    /// Largest first, so smaller tiles are drawn on top and every tile can be seen; tiles saved
    /// at the same place are cascaded for the same reason.
    static func tiles(for workspace: Workspace, on board: CGSize) -> [PreviewTile] {
        let known = Set(workspace.windows.map(\.id))
        let focus = workspace.options.focusedWindow
        var grouped = Set<UUID>()
        var tiles: [PreviewTile] = []
        for group in workspace.tabGroups {
            // An entry is one tab, however often the group names it.
            var tabs: [UUID] = []
            for member in group.members where known.contains(member) && !grouped.contains(member) && !tabs.contains(member) {
                tabs.append(member)
            }
            guard tabs.count >= 2, let first = tabs.first else { continue }
            grouped.formUnion(tabs)
            // Expansion finally focuses this tab, even in older checkpoints whose group.active differs.
            let active = focus.flatMap { tabs.contains($0) ? $0 : nil } ?? (tabs.contains(group.active) ? group.active : first)
            tiles.append(PreviewTile(active: active, tabs: tabs,
                                     rect: rect(group.unitArea, on: board), showsTabBar: true,
                                     isFocused: focus.map(tabs.contains) ?? false))
        }
        for item in workspace.windows where !grouped.contains(item.id) {
            tiles.append(PreviewTile(active: item.id, tabs: [item.id], rect: rect(item.unitFrame, on: board),
                                     showsTabBar: false, isFocused: focus == item.id))
        }
        let places = tiles.map(\.rect)
        for index in tiles.indices {
            let earlier = places[..<index].filter { $0 == places[index] }.count
            tiles[index].rect = cascaded(places[index], steps: earlier, on: board)
        }
        // Stable: equal areas keep groups before entries and the saved order within each.
        return tiles.enumerated().sorted { one, other in
            let (a, b) = (one.element.rect.width * one.element.rect.height, other.element.rect.width * other.element.rect.height)
            return a == b ? one.offset < other.offset : a > b
        }.map(\.element)
    }

    static func tabShowsName(tileWidth: CGFloat, tabs: Int) -> Bool {
        tabs > 0 && tileWidth / CGFloat(tabs) >= 56
    }

    /// `rect` moved `steps` times `cascadeStep` right and down, so the top and left edges of the
    /// tile under it stay in view. At the board's edge it shrinks instead of leaving the board,
    /// down to `minimumSide`.
    private static func cascaded(_ rect: CGRect, steps: Int, on board: CGSize) -> CGRect {
        guard steps > 0 else { return rect }
        let shift = CGFloat(steps) * cascadeStep
        var moved = rect
        moved.size.width = max(min(rect.width, board.width - rect.minX - shift), min(minimumSide, rect.width))
        moved.size.height = max(min(rect.height, board.height - rect.minY - shift), min(minimumSide, rect.height))
        moved.origin.x = min(rect.minX + shift, board.width - moved.width)
        moved.origin.y = min(rect.minY + shift, board.height - moved.height)
        return moved
    }

    /// The part of the unit rectangle that is on the board, never smaller than `minimumSide`.
    private static func rect(_ unit: UnitRect, on board: CGSize) -> CGRect {
        let bounds = CGRect(origin: .zero, size: board)
        let values = [unit.x, unit.y, unit.width, unit.height]
        var rect = values.allSatisfy(\.isFinite) ? unit.frame(in: bounds).intersection(bounds) : .null
        if rect.isNull {
            let x = unit.x.isFinite ? CGFloat(unit.x) * board.width : 0, y = unit.y.isFinite ? CGFloat(unit.y) * board.height : 0
            rect = CGRect(x: x, y: y, width: 0, height: 0)
        }
        rect.size.width = min(max(rect.width, minimumSide), board.width)
        rect.size.height = min(max(rect.height, minimumSide), board.height)
        rect.origin.x = min(max(rect.minX, 0), board.width - rect.width)
        rect.origin.y = min(max(rect.minY, 0), board.height - rect.height)
        return rect
    }
}
