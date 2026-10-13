import Contracts
import CoreGraphics
import CoreKit

/// Moves windows for commands, drags and the placement service, and keeps `WindowMemory` in
/// step with what really happened.
@MainActor
final class WindowMover {
    private let windows: any WindowService
    private(set) var memory = WindowMemory()
    /// Every frame `move` asks a window to take, announced before it is written
    /// (`PlacementService.requests`).
    nonisolated let requests = Broadcaster<PlacementRequest>()
    var animation: FrameAnimation = .standard
    private var tail: Task<Void, Never>?

    init(windows: any WindowService) {
        self.windows = windows
    }

    /// Runs `work` after all work queued before it has finished, so a command reads the
    /// window where the previous one left it instead of halfway through an animation.
    func serially<T: Sendable>(_ work: @escaping @MainActor () async -> T) async -> T {
        await enqueue(work).value
    }

    /// Queues `work` like `serially` without waiting for it, for a drag, which must keep up with
    /// the pointer while the window it dropped is still moving.
    @discardableResult
    func enqueue<T: Sendable>(_ work: @escaping @MainActor () async -> T) -> Task<T, Never> {
        let previous = tail
        let task = Task { @MainActor in
            await previous?.value
            return await work()
        }
        tail = Task { _ = await task.value }
        return task
    }

    /// Moves `window` to `frame`. When the window's minimum size pushes it out of `bounds`, it is
    /// moved back inside once; the size it insists on is accepted (design section 5.3). `frame` is
    /// announced first: it is the place asked for, whatever the window makes of it.
    func move(_ window: WindowInfo, to frame: CGRect, within bounds: CGRect?, kind: MoveKind,
              historyFrame: CGRect? = nil, animation: FrameAnimation? = nil) async -> Result<CGRect, WindowError> {
        requests.send(PlacementRequest(windowID: window.id, frame: frame, isZone: kind == .snap))
        let result = await windows.setFrame(window.id, to: frame, animation: animation ?? self.animation)
        guard case .success(var placed) = result else { return result }
        if let bounds {
            let inside = LayoutGeometry.rounded(RectMath.clamp(placed, to: bounds))
            if !WindowMemory.same(inside, placed),
               case .success(let corrected) = await windows.setFrame(window.id, to: inside, animation: .none) {
                placed = corrected
            }
        }
        remember(window.id, movedFrom: window.frame, to: placed, kind: kind, historyFrame: historyFrame)
        return .success(placed)
    }

    /// Gives a window being dragged out of its snapped place its earlier size. No animation:
    /// the pointer is holding the window.
    func restoreSize(of id: WindowID, to frame: CGRect) async {
        memory.endSnap(id)
        _ = await windows.setFrame(id, to: frame, animation: .none)
    }

    func remember(_ id: WindowID, movedFrom before: CGRect, to after: CGRect, kind: MoveKind,
                  historyFrame: CGRect? = nil) {
        memory.recordMove(id, from: before, to: after, kind: kind, historyFrame: historyFrame)
    }

    func takePrevious(_ id: WindowID, current: CGRect) -> CGRect? {
        memory.takePrevious(id, current: current)
    }

    func restoreSize(for id: WindowID, at frame: CGRect) -> CGSize? {
        memory.restoreSize(for: id, at: frame)
    }

    func snappedWindow(_ id: WindowID, isAt frame: CGRect) {
        memory.snappedWindow(id, isAt: frame)
    }

    func forget(_ id: WindowID) {
        memory.forget(id)
    }
}
