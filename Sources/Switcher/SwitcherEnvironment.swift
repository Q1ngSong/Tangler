import AppKit
import Contracts
import OverlayKit

/// What the switcher needs from the system besides the module context's services.
/// Tests replace all of it, so no test shows a panel or reads the real keyboard.
@MainActor
struct SwitcherEnvironment {
    var presenter: any SwitcherPresenter
    /// The pointer in global coordinates.
    var pointer: @MainActor () -> CGPoint
    /// The modifier keys held right now.
    var heldModifiers: @MainActor () -> Modifiers
    /// Waits before live frames start; see `ThumbnailFeed.settleDelay`.
    var pause: ThumbnailFeed.Pause

    static func system() -> SwitcherEnvironment {
        SwitcherEnvironment(presenter: OverlaySwitcherPresenter(),
                            pointer: { OverlayGeometry.mouseLocation },
                            heldModifiers: { HoldModifiers.modifiers(from: NSEvent.modifierFlags) },
                            pause: { try? await Task.sleep(for: $0) })
    }
}
