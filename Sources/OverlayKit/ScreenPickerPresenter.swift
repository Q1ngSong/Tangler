import AppKit

/// Covers every display with a picker panel above all windows and menus.
@MainActor
final class ScreenPickerPresenter: WindowPickerPresenter {
    private var panels: [OverlayPanel] = []
    /// A regular Tangler window, e.g. Settings, put away so it does not hide the windows to pick.
    private weak var hiddenWindow: NSWindow?

    func present(model: WindowPickerModel, prompt: String, onInput: @escaping (WindowPickerInput) -> Void) {
        dismiss()
        hideKeyWindow()
        let primaryHeight = OverlayGeometry.primaryDisplayHeight
        let pointer = NSEvent.mouseLocation
        var pointerPanel: OverlayPanel?
        for screen in NSScreen.screens {
            let canvas = OverlayGeometry.globalFrame(fromAppKit: screen.frame, primaryHeight: primaryHeight)
            let panel = OverlayPanel(style: .picker)
            panel.acceptsMouseMovedEvents = true
            panel.contentView = PickerSurfaceView(model: model, canvas: canvas, prompt: prompt,
                                                  primaryHeight: primaryHeight, onInput: onInput)
            panel.setFrame(screen.frame, display: false)
            panel.orderFrontRegardless()
            panels.append(panel)
            if screen.frame.contains(pointer) { pointerPanel = panel }
        }
        // Esc reaches only the key panel; the user looks at the display with the pointer.
        if let panel = pointerPanel ?? panels.first {
            panel.makeKey()
            panel.makeFirstResponder(panel.contentView)
        }
        // Highlight what is under the pointer before it first moves.
        onInput(.moved(OverlayGeometry.globalPoint(fromAppKit: pointer, primaryHeight: primaryHeight)))
    }

    func dismiss() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        hiddenWindow?.makeKeyAndOrderFront(nil)
        hiddenWindow = nil
    }

    private func hideKeyWindow() {
        guard let key = NSApp.keyWindow, !(key is OverlayPanel) else { return }
        let window = key.sheetParent ?? key
        window.orderOut(nil)
        hiddenWindow = window
    }
}
