import CoreGraphics
import OverlayKit

/// What the module uses besides its context: the screen and the clock, which tests replace.
@MainActor
struct PaletteEnvironment {
    var leaderPresenter: any LeaderPresenting
    var palettePresenter: any PalettePresenting
    var scheduler: any Scheduling
    /// The pointer in global coordinates, for when no window says which display to use.
    var pointer: () -> CGPoint

    static func live() -> PaletteEnvironment {
        PaletteEnvironment(leaderPresenter: OverlayLeaderPresenter(), palettePresenter: OverlayPalettePresenter(),
                           scheduler: TaskScheduler(), pointer: { OverlayGeometry.mouseLocation })
    }
}
