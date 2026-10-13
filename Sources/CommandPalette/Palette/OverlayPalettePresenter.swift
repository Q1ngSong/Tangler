import AppKit
import OverlayKit

/// Shows the palette in a panel that takes the keyboard without activating Tangler, and reports
/// when it loses the keyboard because the user clicked elsewhere.
@MainActor
final class OverlayPalettePresenter: PalettePresenting {
    private let host = OverlayHost<PaletteView>(style: .keyboard)
    private var onKeyLost: (() -> Void)?
    // Only read in deinit to remove it; NotificationCenter may be called from any thread.
    nonisolated(unsafe) private var observer: (any NSObjectProtocol)?

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func show(_ model: PaletteModel, in frame: CGRect, actions: PaletteActions) {
        onKeyLost = actions.dismiss
        host.show(PaletteView(model: model, actions: actions), in: frame)
        observeKeyLoss()
    }

    func hide() {
        // Cleared first: hiding the panel also takes the keyboard from it, and that is not the user leaving.
        onKeyLost = nil
        host.hide()
    }

    private func observeKeyLoss() {
        guard observer == nil, let panel = host.panel else { return }
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onKeyLost?() }
        }
    }
}
