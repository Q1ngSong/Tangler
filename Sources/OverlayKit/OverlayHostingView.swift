import AppKit
import SwiftUI

/// Hosting view for overlay panels. Overlays are never active and usually never key, so
/// without first-mouse the first click on a button would be swallowed.
final class OverlayHostingView<Content: View>: NSHostingView<Content> {
    /// Draws only; mouse events go to the view behind it.
    var passesMouseEvents = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        passesMouseEvents ? nil : super.hitTest(point)
    }

    /// Lays SwiftUI out in whatever frame the host sets, and ignores the notch's safe area
    /// so content covering a whole display lines up with global coordinates.
    func configureForOverlay() {
        sizingOptions = []
        safeAreaRegions = []
    }
}
