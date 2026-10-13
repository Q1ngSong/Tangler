import AppKit
import OverlayKit
import SwiftUI

/// Shows messages and expansion reports in a click-through panel in the lower half of the display
/// under the pointer. Finished reports and messages fade out by themselves.
@MainActor
final class HUDNotifier: WorkspaceNotifying {
    private let host = OverlayHost<WorkspaceHUDView>(style: .hud)
    private var hideTask: Task<Void, Never>?

    func show(_ report: ExpansionReport) {
        present(.expansion(report), hidingAfter: report.isFinished ? .seconds(6) : nil)
    }

    func show(message: String) {
        present(.message(message), hidingAfter: .seconds(3))
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        host.hide()
    }

    private func present(_ content: WorkspaceHUDView.Content, hidingAfter delay: Duration?) {
        hideTask?.cancel()
        hideTask = nil
        guard let area = Self.area() else { return }
        host.show(WorkspaceHUDView(content: content), placement: .centered(in: area))
        guard let delay else { return }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.host.hide()
        }
    }

    /// The lower half of the visible frame of the display under the pointer, in global coordinates.
    private static func area() -> CGRect? {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) })
            ?? NSScreen.screens.first else { return nil }
        let visible = OverlayGeometry.globalFrame(fromAppKit: screen.visibleFrame,
                                                  primaryHeight: OverlayGeometry.primaryDisplayHeight)
        return CGRect(x: visible.minX, y: visible.midY, width: visible.width, height: visible.height / 2)
    }
}
