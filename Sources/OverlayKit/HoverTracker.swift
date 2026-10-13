import AppKit
import SwiftUI

/// Reports the pointer entering and leaving the view. Unlike SwiftUI's hover tracking it
/// works in panels that are not key while Tangler is inactive, which is how overlays run.
/// Clicks pass through to the SwiftUI content around it.
struct HoverTracker: NSViewRepresentable {
    var onChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onChange = onChange
    }

    final class TrackingView: NSView {
        var onChange: ((Bool) -> Void)?
        private var trackingArea: NSTrackingArea?
        private var isInside = false

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea { removeTrackingArea(trackingArea) }
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                      owner: self)
            addTrackingArea(area)
            trackingArea = area
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func mouseEntered(with event: NSEvent) { report(true) }
        override func mouseExited(with event: NSEvent) { report(false) }

        private func report(_ inside: Bool) {
            guard inside != isInside else { return }
            isInside = inside
            onChange?(inside)
        }
    }
}

public extension View {
    /// Calls `action` as the pointer enters and leaves the view, also in overlay panels that are not
    /// key while Tangler is inactive, where SwiftUI's `onHover` stays silent.
    func onOverlayHover(_ action: @escaping (Bool) -> Void) -> some View {
        background(HoverTracker(onChange: action))
    }
}
