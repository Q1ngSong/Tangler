import Contracts
import CoreGraphics

/// Dragging a window onto a tab bar with ⌘ (tab groups design 4.2 item 4), as plain state fed
/// in the order things happened. A press becomes a window drag when the pressed window reports
/// a move of the same size, as in the layout module, so resizing from an edge never joins.
/// Only a drag that began with ⌘ alone held joins; it pulls the window out of its group at once.
struct JoinDragTracker {
    /// Where a ⌘-dragged window can land: one per bar on screen.
    struct Zone: Equatable {
        var group: TabGroupID
        /// Where the pointer counts as over the bar.
        var frame: CGRect
        /// The bar as drawn, for the slot.
        var bar: CGRect
        /// How many tabs the bar would hold with the dragged window in it.
        var slots: Int
    }

    struct Target: Equatable {
        var group: TabGroupID
        /// The slot the window or tab would take, counted with it in the bar: 0 is the leftmost.
        var index: Int
    }

    enum Effect: Equatable {
        /// A ⌘-drag of the window began: it leaves its group.
        case pullOut(WindowID)
        /// Show the window where it would land.
        case preview(WindowID, Target)
        /// Take the preview away.
        case clearPreview
        case join(WindowID, Target)
    }

    private enum Phase: Equatable {
        case idle
        case pressed(WindowID, CGRect)
        case dragging(WindowID, joins: Bool)
        case ignoring
    }

    private var phase = Phase.idle
    private var modifiers: Modifiers = []
    private var pointer = CGPoint.zero
    private(set) var target: Target?

    /// ⌘ alone; fn does not count, since macOS sets it on arrow keys and some mice.
    static func joins(with modifiers: Modifiers) -> Bool { modifiers.subtracting(.function) == .command }

    mutating func buttonDown(at point: CGPoint, modifiers: Modifiers, window: (id: WindowID, frame: CGRect)?) -> [Effect] {
        let stale = clearTarget()
        pointer = point
        self.modifiers = modifiers
        phase = window.map { .pressed($0.id, $0.frame) } ?? .ignoring
        return stale
    }

    mutating func windowMoved(_ id: WindowID, to frame: CGRect, zones: [Zone]) -> [Effect] {
        guard case .pressed(let pressed, let start) = phase, pressed == id, !TabGeometry.same(frame, start) else { return [] }
        guard TabGeometry.sameSize(frame, start) else {
            phase = .ignoring
            return []
        }
        let joins = Self.joins(with: modifiers)
        phase = .dragging(id, joins: joins)
        return joins ? [.pullOut(id)] + retarget(zones) : []
    }

    mutating func pointerMoved(to point: CGPoint, modifiers: Modifiers, zones: [Zone]) -> [Effect] {
        pointer = point
        self.modifiers = modifiers
        return retarget(zones)
    }

    mutating func modifiersChanged(_ modifiers: Modifiers, zones: [Zone]) -> [Effect] {
        self.modifiers = modifiers
        return retarget(zones)
    }

    mutating func buttonUp(at point: CGPoint, modifiers: Modifiers, zones: [Zone]) -> [Effect] {
        pointer = point
        self.modifiers = modifiers
        defer { phase = .idle }
        guard case .dragging(let id, true) = phase else { return clearTarget() }
        let changes = retarget(zones)
        guard let target else { return changes }
        self.target = nil
        return [.clearPreview, .join(id, target)]
    }

    mutating func windowGone(_ id: WindowID) -> [Effect] {
        switch phase {
        case .pressed(id, _), .dragging(id, _):
            phase = .ignoring
            return clearTarget()
        case .idle, .pressed, .dragging, .ignoring:
            return []
        }
    }

    private mutating func retarget(_ zones: [Zone]) -> [Effect] {
        guard case .dragging(let id, true) = phase else { return clearTarget() }
        var fresh: Target?
        if Self.joins(with: modifiers), let zone = zones.first(where: { $0.frame.contains(pointer) }) {
            let layout = TabBarLayout(barWidth: zone.bar.width, count: zone.slots)
            fresh = Target(group: zone.group, index: layout.slot(atX: pointer.x - zone.bar.minX))
        }
        guard fresh != target else { return [] }
        target = fresh
        return [fresh.map { .preview(id, $0) } ?? .clearPreview]
    }

    private mutating func clearTarget() -> [Effect] {
        guard target != nil else { return [] }
        target = nil
        return [.clearPreview]
    }
}
