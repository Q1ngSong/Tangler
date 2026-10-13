import Contracts
import CoreGraphics
import Observation

/// The window under the pointer while picking. Pointer moves arrive far faster than window
/// lookups finish, so only one lookup runs at a time and it continues with the newest position.
@MainActor
@Observable
final class WindowPickerModel {
    typealias Resolve = (CGPoint) async -> WindowInfo?

    private(set) var candidate: WindowInfo?

    @ObservationIgnored private let resolve: Resolve
    @ObservationIgnored private var pendingPoint: CGPoint?
    @ObservationIgnored private var isResolving = false
    /// Changes on `reset()`, so answers to lookups started before it are dropped.
    @ObservationIgnored private var generation = 0

    init(resolve: @escaping Resolve) {
        self.resolve = resolve
    }

    func reset() {
        generation += 1
        pendingPoint = nil
        candidate = nil
    }

    func hover(at point: CGPoint) async {
        pendingPoint = point
        guard !isResolving else { return }
        isResolving = true
        defer { isResolving = false }
        while let next = pendingPoint {
            pendingPoint = nil
            let started = generation
            let window = await resolve(next)
            if generation == started { candidate = window }
        }
    }

    /// A fresh lookup for a click, since the highlighted window may lag behind the pointer.
    func window(at point: CGPoint) async -> WindowInfo? {
        await resolve(point)
    }

    /// Looks windows up through `windows`, skipping Tangler's own, such as its Settings window.
    static func resolver(for windows: any WindowService, ignoring ownPID: Int32) -> Resolve {
        { point in
            guard let id = await windows.windowID(at: point), let window = await windows.window(id),
                  window.pid != ownPID else { return nil }
            return window
        }
    }
}
