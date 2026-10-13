import CoreGraphics
import OverlayKit

/// Puts the preview on screen. The real one is an overlay panel; tests use a recorder.
@MainActor
protocol DockPreviewPresenting: AnyObject {
    /// Whether showing, moving and hiding are animated; from the settings.
    var animates: Bool { get set }
    /// Shows `content` at its layout size, replacing what is shown; returns the global frame.
    func show(_ content: DockPreviewContent, placement: OverlayPlacement, actions: DockPreviewActions) -> CGRect
    func hide()
}
