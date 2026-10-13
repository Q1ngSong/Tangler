import Contracts
import CoreGraphics
import CoreKit

/// Places windows by display and relative frame for Workspaces (design sections 3.3 and 4.5).
/// A whole batch is one queued move, so commands never interleave with a restore.
@MainActor
final class LayoutPlacementService: PlacementService {
    private let windows: any WindowService
    private let mover: WindowMover
    private nonisolated let announced: Broadcaster<PlacementRequest>

    init(windows: any WindowService, mover: WindowMover) {
        self.windows = windows
        self.mover = mover
        announced = mover.requests
    }

    /// Every move the mover makes: drags and commands as well as `apply`.
    nonisolated func requests() -> AsyncStream<PlacementRequest> { announced.stream() }

    func apply(_ placements: [Placement]) async -> [WindowID: PlacementOutcome] {
        // One placement per window; the last one wins, as it would if they ran in order.
        var latest: [WindowID: Placement] = [:]
        for placement in placements { latest[placement.windowID] = placement }
        let batch = Array(latest.values)
        return await mover.serially { [self] in
            let displays = await windows.displays()
            return await withTaskGroup(of: (WindowID, PlacementOutcome).self) { group in
                for placement in batch {
                    group.addTask { @MainActor in (placement.windowID, await self.place(placement, displays: displays)) }
                }
                var outcomes: [WindowID: PlacementOutcome] = [:]
                for await (id, outcome) in group { outcomes[id] = outcome }
                return outcomes
            }
        }
    }

    func currentPlacement(of id: WindowID) async -> Placement? {
        guard let window = await windows.window(id),
              let display = DisplayLookup.display(for: window, in: await windows.displays()) else { return nil }
        return Placement(windowID: id, displayID: display.id, spaceID: window.spaceIDs.count == 1 ? window.spaceIDs[0] : nil,
                         unitFrame: UnitRect(frame: window.frame, in: display.visibleFrame), absoluteFrame: window.frame)
    }

    private func place(_ placement: Placement, displays: [DisplayInfo]) async -> PlacementOutcome {
        guard let window = await windows.window(placement.windowID) else { return .windowMissing }
        guard !window.isFullscreen else { return .failed(.rejected(L10n.text("windowlayout.full.screen.windows.cannot.be.moved"))) }
        let saved = displays.first { $0.id == placement.displayID }
        guard let display = saved ?? DisplayLookup.main(in: displays) else { return .failed(.rejected(L10n.text("windowlayout.could.not.read.the.display.list"))) }
        let bounds = display.visibleFrame
        let frame = LayoutGeometry.rounded(RectMath.clamp(target(of: placement, in: bounds, current: window.frame), to: bounds))
        let placed: CGRect
        switch await mover.move(window, to: frame, within: bounds, kind: .reposition) {
        case .success(let readBack): placed = readBack
        case .failure(let error): return .failed(error)
        }
        // Without the private ability the window stays on its desktop, as when no Space was saved;
        // a window shown on every desktop is already there.
        if let space = placement.spaceID, windows.capabilities.contains(.moveAcrossSpaces),
           window.spaceIDs.count <= 1, window.spaceIDs.first != space,
           case .failure(let error) = await windows.move(window.id, toSpace: space) {
            return .failed(error)
        }
        return saved == nil ? .placedOnFallbackDisplay(placed) : .placed(placed)
    }

    /// The relative frame, or the absolute one when the relative frame has no area.
    private func target(of placement: Placement, in bounds: CGRect, current: CGRect) -> CGRect {
        let unit = placement.unitFrame
        let usable = [unit.x, unit.y, unit.width, unit.height].allSatisfy(\.isFinite) && unit.width > 0 && unit.height > 0
        if usable { return unit.frame(in: bounds) }
        return placement.absoluteFrame ?? current
    }
}
