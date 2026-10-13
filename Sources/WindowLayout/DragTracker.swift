import Contracts
import CoreGraphics
import CoreKit

/// What the preview overlay draws: where the window will go, over one display.
struct SnapPreview: Equatable, Sendable {
    /// The display's frame, which the overlay covers.
    var canvas: CGRect
    /// The display's visible frame, which targets and grid cells fill.
    var bounds: CGRect
    var target: CGRect
    /// Every cell while the grid is showing.
    var gridCells: [CGRect]?
    /// The dragged window, which the overlay sits just below.
    var window: WindowID? = nil
    /// Where the dragged window was when the preview appeared: the first preview grows from
    /// there. It stays the same while the preview shows on the same display; a preview on
    /// another display takes the window's frame afresh.
    var origin: CGRect? = nil

    /// Compares what the overlay draws; `window` and `origin` ride along and are never
    /// compared, so fixtures need not set them. Add any new drawn property here by hand; a
    /// Hashable conformance would need `hash(into:)` over the same fields.
    static func == (lhs: SnapPreview, rhs: SnapPreview) -> Bool {
        lhs.canvas == rhs.canvas && lhs.bounds == rhs.bounds && lhs.target == rhs.target
            && lhs.gridCells == rhs.gridCells
    }
}

enum DragEffect: Equatable, Sendable {
    case show(SnapPreview)
    case hide
    /// The window is leaving its snapped place: put it here, at its earlier size.
    case restoreSize(WindowID, CGRect)
    /// Released over a target. `startFrame` is where the drag began, for going back.
    case place(WindowID, frame: CGRect, bounds: CGRect, startFrame: CGRect)
    /// Released before any move of the pressed window arrived. A flick that quick may have moved
    /// it anyway, unseen by the drag.
    case releasedUnmoved(WindowID)
}

/// The window under the pointer when the left button went down.
struct PressedWindow: Equatable, Sendable {
    var id: WindowID
    var frame: CGRect
    /// The size to give back once the window moves, when it sits where Tangler snapped it.
    var restoreSize: CGSize?
}

/// Drag snapping as plain state (design section 4.1, batch 2 plan A.1–A.4). A press only
/// becomes a window drag when the pressed window reports a move of the same size, so
/// selecting text or resizing from an edge never snaps. Fed in the order events happened.
struct DragTracker {
    private enum Phase: Equatable {
        case idle
        case pressed(PressedWindow)
        case dragging(Drag)
        /// Esc, a resize, another button or no window: nothing happens until the button is up.
        case ignoring
    }

    private struct Drag: Equatable {
        var window: PressedWindow
        var gridAnchor: GridAnchor?
        var preview: SnapPreview?
    }

    private struct GridAnchor: Equatable {
        var cell: GridCell
        var display: DisplayID
    }

    private(set) var settings: LayoutSettings
    private(set) var displays: [DisplayInfo]
    private var phase = Phase.idle
    /// Where the left button went down.
    private var press = CGPoint.zero
    /// When the button checks of this press began finding the button up.
    private var upSince: ContinuousClock.Instant?
    private var pointer = CGPoint.zero
    private var modifiers: Modifiers = []

    init(settings: LayoutSettings, displays: [DisplayInfo]) {
        self.settings = settings
        self.displays = displays
    }

    var isPreviewing: Bool {
        if case .dragging(let drag) = phase { return drag.preview != nil }
        return false
    }

    /// The window under the button while it has not moved yet.
    var pressedWindowID: WindowID? {
        if case .pressed(let window) = phase { return window.id }
        return nil
    }

    mutating func buttonDown(_ event: MouseEvent, on window: PressedWindow?) -> [DragEffect] {
        guard event.button == .left else { return [] }
        let stale: [DragEffect] = isPreviewing ? [.hide] : []
        press = event.location
        upSince = nil
        pointer = event.location
        modifiers = event.modifiers
        phase = window.map(Phase.pressed) ?? .ignoring
        return stale
    }

    mutating func pointerMoved(_ event: MouseEvent) -> [DragEffect] {
        guard event.button == .left else { return [] }
        pointer = event.location
        modifiers = event.modifiers
        return retarget()
    }

    mutating func modifiersChanged(_ modifiers: Modifiers) -> [DragEffect] {
        self.modifiers = modifiers
        return retarget()
    }

    mutating func windowMoved(_ id: WindowID, to frame: CGRect) -> [DragEffect] {
        guard case .pressed(let window) = phase, window.id == id else { return [] }
        // WindowKit can answer the press's read late, then report the very frame it answered
        // with, e.g. while the left edge is being dragged: that is no move.
        guard !WindowMemory.same(frame, window.frame) else { return [] }
        guard WindowMemory.sameSize(frame, window.frame) else {
            // Dragging the left or top edge moves the window too, but changes its size.
            phase = .ignoring
            return []
        }
        phase = .dragging(Drag(window: window))
        let preview = retarget()
        guard window.restoreSize != nil else { return preview }
        return preview + [.restoreSize(id, currentFrame(of: window))]
    }

    mutating func windowResized(_ id: WindowID) -> [DragEffect] {
        if case .pressed(let window) = phase, window.id == id { phase = .ignoring }
        return []
    }

    mutating func windowGone(_ id: WindowID) -> [DragEffect] {
        switch phase {
        case .pressed(let window) where window.id == id:
            phase = .ignoring
        case .dragging(let drag) where drag.window.id == id:
            phase = .ignoring
            return drag.preview == nil ? [] : [.hide]
        case .idle, .pressed, .dragging, .ignoring:
            break
        }
        return []
    }

    mutating func buttonUp(_ event: MouseEvent) -> [DragEffect] {
        guard event.button == .left else { return [] }
        pointer = event.location
        modifiers = event.modifiers
        defer { phase = .idle }
        if case .pressed(let window) = phase { return [.releasedUnmoved(window.id)] }
        // Only a drag that showed a preview places the window: nothing happens unseen.
        guard case .dragging(var drag) = phase, drag.preview != nil else { return [] }
        guard let target = target(for: &drag) else { return [.hide] }
        return [.hide, .place(drag.window.id, frame: target.target, bounds: target.bounds, startFrame: drag.window.frame)]
    }

    mutating func escape() -> [DragEffect] {
        guard isPreviewing else { return [] }
        phase = .ignoring
        return [.hide]
    }

    /// The button is up although its release never arrived: drop the drag, placing nothing.
    mutating func abandon() -> [DragEffect] {
        let effects: [DragEffect] = isPreviewing ? [.hide] : []
        phase = .idle
        return effects
    }

    /// How long the button must have been up, by the checks, before its release counts as lost.
    static let lostReleaseWait: Duration = .milliseconds(200)

    /// A check, made at `time` while the preview shows, of whether the left button is down:
    /// another event tap can take the release, leaving the preview up and the keyboard swallowed.
    /// The release counts as lost once checks `lostReleaseWait` apart have found the button up
    /// throughout. By then one still on its way has had that long to reach the queue, while
    /// checks piled up by a stall, made one right after the other, are as good as one.
    mutating func buttonChecked(isDown: Bool, at time: ContinuousClock.Instant) -> [DragEffect] {
        guard isPreviewing else { return [] }
        guard !isDown else {
            upSince = nil
            return []
        }
        guard let upSince else {
            self.upSince = time
            return []
        }
        return time - upSince >= Self.lostReleaseWait ? abandon() : []
    }

    mutating func update(settings: LayoutSettings) -> [DragEffect] {
        self.settings = settings
        return retarget()
    }

    mutating func update(displays: [DisplayInfo]) -> [DragEffect] {
        self.displays = displays
        return retarget()
    }

    /// `size` put under the pointer the way the window was pressed: the pointer keeps its share
    /// of the title bar's width and its distance below the top edge. Worked out from the press
    /// rather than from a reported move, which lags behind a quick drag.
    static func restoredFrame(size: CGSize, pressedAt press: CGPoint, on pressed: CGRect, pointer: CGPoint) -> CGRect {
        let share = pressed.width > 0 ? min(max((press.x - pressed.minX) / pressed.width, 0), 1) : 0.5
        let below = min(max(press.y - pressed.minY, 0), size.height)
        return CGRect(x: (pointer.x - share * size.width).rounded(), y: (pointer.y - below).rounded(),
                      width: size.width, height: size.height)
    }

    private mutating func retarget() -> [DragEffect] {
        guard case .dragging(var drag) = phase else { return [] }
        var preview = target(for: &drag)
        if var fresh = preview {
            fresh.window = drag.window.id
            // Kept while a preview shows on the same display; taken afresh when one appears.
            if let kept = drag.preview, kept.canvas == fresh.canvas {
                fresh.origin = kept.origin
            } else {
                var frame = currentFrame(of: drag.window)
                // A real window never goes above its display's menu bar.
                frame.origin.y = max(frame.minY, fresh.bounds.minY)
                fresh.origin = frame
            }
            preview = fresh
        }
        let changed = preview != drag.preview
        drag.preview = preview
        phase = .dragging(drag)
        guard changed else { return [] }
        return [preview.map(DragEffect.show) ?? .hide]
    }

    /// Where the dragged window is now: it follows the pointer, at its restored size once a
    /// drag-out restore gave it back.
    private func currentFrame(of window: PressedWindow) -> CGRect {
        if let size = window.restoreSize {
            return Self.restoredFrame(size: size, pressedAt: press, on: window.frame, pointer: pointer)
        }
        return window.frame.offsetBy(dx: pointer.x - press.x, dy: pointer.y - press.y)
    }

    /// The grid while its modifiers are held, otherwise the edge under the pointer. Targets
    /// fill the visible frame.
    private func target(for drag: inout Drag) -> SnapPreview? {
        guard let display = DisplayLookup.display(at: pointer, in: displays),
              display.visibleFrame.isFiniteRect, !display.visibleFrame.isEmpty else {
            drag.gridAnchor = nil
            return nil
        }
        let bounds = display.visibleFrame
        let gap = settings.gapPoints
        if settings.gridIsHeld(by: modifiers) {
            // Over the menu bar or the Dock the pointer still picks the nearest cell.
            let grid = settings.snapGrid
            guard let cell = grid.cell(at: Self.point(pointer, inside: bounds), in: bounds) else { return nil }
            if drag.gridAnchor?.display != display.id { drag.gridAnchor = GridAnchor(cell: cell, display: display.id) }
            let anchor = drag.gridAnchor?.cell ?? cell
            return SnapPreview(canvas: display.frame, bounds: bounds,
                               target: LayoutGeometry.rounded(grid.frame(from: anchor, to: cell, in: bounds, gap: gap)),
                               gridCells: grid.cellFrames(in: bounds))
        }
        drag.gridAnchor = nil
        // Edges are measured on the whole display: the top one is the menu bar, which a window
        // cannot enter, so merely moving a window to the top of the screen never maximizes it.
        guard settings.edgeSnapping,
              let edge = OuterEdges.target(at: Self.point(pointer, inside: display.frame), on: display,
                                           among: displays) else {
            return nil
        }
        return SnapPreview(canvas: display.frame, bounds: bounds,
                           target: LayoutGeometry.rounded(edge.frame(in: bounds, gap: gap)), gridCells: nil)
    }

    /// `point` moved into `rect`, whose right and bottom edges are outside it.
    private static func point(_ point: CGPoint, inside rect: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, rect.minX), rect.maxX - 0.5), y: min(max(point.y, rect.minY), rect.maxY - 0.5))
    }
}
