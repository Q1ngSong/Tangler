import AppKit
import Contracts
import CoreKit
import SwiftUI

/// One display's share of the window picker. It shows `WindowPickerOverlay` and turns
/// pointer moves, clicks, right clicks and Esc into picker input in global coordinates.
final class PickerSurfaceView: NSView {
    private let onInput: (WindowPickerInput) -> Void
    private let primaryHeight: CGFloat
    private var trackingArea: NSTrackingArea?

    init(model: WindowPickerModel, canvas: CGRect, prompt: String, primaryHeight: CGFloat,
         onInput: @escaping (WindowPickerInput) -> Void) {
        self.onInput = onInput
        self.primaryHeight = primaryHeight
        super.init(frame: CGRect(origin: .zero, size: canvas.size))
        let drawing = OverlayHostingView(rootView: SkinnedRoot(content: WindowPickerOverlay(model: model, canvas: canvas,
                                                                                            prompt: prompt)))
        drawing.configureForOverlay()
        drawing.passesMouseEvents = true
        drawing.frame = bounds
        drawing.autoresizingMask = [.width, .height]
        addSubview(drawing)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseMoved(with event: NSEvent) {
        onInput(.moved(globalLocation(of: event)))
    }

    override func mouseDown(with event: NSEvent) {
        onInput(.clicked(globalLocation(of: event)))
    }

    override func rightMouseDown(with event: NSEvent) {
        onInput(.cancelled)
    }

    /// Other keys are swallowed so they neither beep nor reach another window.
    override func keyDown(with event: NSEvent) {
        if KeyCodes.name(for: event.keyCode) == Key.escape.rawValue { onInput(.cancelled) }
    }

    private func globalLocation(of event: NSEvent) -> CGPoint {
        let point = window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        return OverlayGeometry.globalPoint(fromAppKit: point, primaryHeight: primaryHeight)
    }
}
