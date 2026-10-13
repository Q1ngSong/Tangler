import CoreGraphics

/// Where one window should go. Saved inside workspaces.
public struct Placement: Equatable, Codable, Sendable {
    public var windowID: WindowID
    public var displayID: DisplayID
    /// nil keeps the window on its current Space.
    public var spaceID: SpaceID?
    /// Position relative to the display's visible frame.
    public var unitFrame: UnitRect
    /// Last known absolute frame, kept for diagnostics and as a fallback.
    public var absoluteFrame: CGRect?

    public init(windowID: WindowID, displayID: DisplayID, spaceID: SpaceID? = nil,
                unitFrame: UnitRect, absoluteFrame: CGRect? = nil) {
        self.windowID = windowID
        self.displayID = displayID
        self.spaceID = spaceID
        self.unitFrame = unitFrame
        self.absoluteFrame = absoluteFrame
    }
}

public enum PlacementOutcome: Equatable, Sendable {
    case placed(CGRect)
    /// The saved display is gone; the window went to the main display instead.
    case placedOnFallbackDisplay(CGRect)
    case windowMissing
    case failed(WindowError)
}

/// A frame the layout is about to ask a window to take.
public struct PlacementRequest: Equatable, Sendable {
    public var windowID: WindowID
    /// The frame asked for, in global coordinates. The window may make another size of it, as one
    /// sized in character cells does.
    public var frame: CGRect
    /// Whether the frame is a place to fill: a half, a quarter, the whole screen, an edge zone, grid
    /// cells. Otherwise it is the window's own frame somewhere: centred, on another display, back
    /// where it was, where a workspace saved it. A tab group fills a place, its bar inside the top;
    /// around its window's own frame the bar goes above.
    public var isZone: Bool

    public init(windowID: WindowID, frame: CGRect, isZone: Bool) {
        self.windowID = windowID
        self.frame = frame
        self.isZone = isZone
    }
}

/// Places several windows at once. Implemented by WindowLayout and used by Workspaces and
/// TabGroups, so no feature module imports another (design section 3.3).
public protocol PlacementService: AnyObject, Sendable {
    func apply(_ placements: [Placement]) async -> [WindowID: PlacementOutcome]
    func currentPlacement(of id: WindowID) async -> Placement?
    /// A new stream, for each caller, of every frame the layout asks a window to take from now on:
    /// by a drag onto an edge or the grid, a layout command, going back, `apply`. Each is announced
    /// before the window is written, so before the window service reports the window there. Tab
    /// groups read it: what a window made of a frame does not say which frame it was asked.
    /// Windows that the user or their applications move are not announced.
    func requests() -> AsyncStream<PlacementRequest>
}
