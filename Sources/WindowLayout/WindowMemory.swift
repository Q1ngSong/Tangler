import Contracts
import CoreGraphics

/// How a move Tangler made changes the window's snap record.
enum MoveKind: Equatable, Sendable {
    /// Halves, quarters, maximize, edge and grid snaps: the window takes a tiled size.
    case snap
    /// Center, another display, the placement service: a snapped window stays snapped.
    case reposition
    /// "回到上一次的位置": the frame came out of the history.
    case undo
}

struct SnapRecord: Equatable, Sendable {
    /// The frame before the window was first snapped; dragging it out gives this size back.
    var restoreFrame: CGRect
    /// Where Tangler last put it. While the window keeps this size it counts as snapped, wherever
    /// it is: a drag moves a window without resizing it, and WindowKit may read a pressed window
    /// only after a quick drag has carried it away.
    var snappedFrame: CGRect
}

/// What Tangler remembers about the windows it moved: earlier frames for "回到上一次的位置"
/// and the size to give back when a snapped window is dragged out (design section 4.1).
struct WindowMemory {
    static let historyLimit = 10
    /// Frames this close count as the same: apps round sizes and the user's hand is not exact.
    static let tolerance: CGFloat = 2

    /// Oldest first.
    private var history: [WindowID: [CGRect]] = [:]
    private var snaps: [WindowID: SnapRecord] = [:]

    func previousFrames(of id: WindowID) -> [CGRect] { history[id] ?? [] }
    func snapRecord(for id: WindowID) -> SnapRecord? { snaps[id] }

    /// Records a move from `before` to `after`, the read-back. `historyFrame` is what
    /// "回到上一次的位置" returns to when it differs from `before`, e.g. where a drag started.
    mutating func recordMove(_ id: WindowID, from before: CGRect, to after: CGRect, kind: MoveKind,
                             historyFrame: CGRect? = nil) {
        if kind != .undo { push(historyFrame ?? before, for: id, unless: after) }
        let record = snaps[id].flatMap { Self.sameSize($0.snappedFrame, before) ? $0 : nil }
        // A window with its unsnapped size has nothing to give back, so no record is kept that a
        // move the drag does not see could leave behind.
        switch kind {
        case .snap:
            let restore = record?.restoreFrame ?? before
            snaps[id] = Self.sameSize(restore, after) ? nil : SnapRecord(restoreFrame: restore, snappedFrame: after)
        case .reposition, .undo:
            guard var record, !Self.sameSize(after, record.restoreFrame) else {
                snaps[id] = nil
                return
            }
            record.snappedFrame = after
            snaps[id] = record
        }
    }

    /// The newest earlier frame that differs from `current`, taken out of the history.
    mutating func takePrevious(_ id: WindowID, current: CGRect) -> CGRect? {
        while let frame = history[id]?.popLast() {
            if !Self.same(frame, current) { return frame }
        }
        return nil
    }

    /// The size to give back when the window, now at `frame`, is dragged out of its snapped place.
    func restoreSize(for id: WindowID, at frame: CGRect) -> CGSize? {
        guard let record = snaps[id], Self.sameSize(record.snappedFrame, frame),
              !Self.sameSize(record.restoreFrame, frame) else { return nil }
        return record.restoreFrame.size
    }

    /// The window was found at `frame` without Tangler moving it there, e.g. after a flick too
    /// quick for the drag to see. Still the snapped size, it is snapped there now.
    mutating func snappedWindow(_ id: WindowID, isAt frame: CGRect) {
        guard var record = snaps[id], Self.sameSize(record.snappedFrame, frame) else { return }
        record.snappedFrame = frame
        snaps[id] = record
    }

    mutating func endSnap(_ id: WindowID) {
        snaps[id] = nil
    }

    mutating func forget(_ id: WindowID) {
        snaps[id] = nil
        history[id] = nil
    }

    static func same(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.maxX - b.maxX) <= tolerance && abs(a.maxY - b.maxY) <= tolerance
    }

    static func sameSize(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    private mutating func push(_ frame: CGRect, for id: WindowID, unless current: CGRect) {
        guard !Self.same(frame, current) else { return }
        var frames = history[id] ?? []
        if let newest = frames.last, Self.same(newest, frame) { return }
        frames.append(frame)
        history[id] = Array(frames.suffix(Self.historyLimit))
    }
}
