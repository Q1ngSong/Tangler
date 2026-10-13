import CoreGraphics
import OverlayKit

/// Puts the switcher on screen.
@MainActor
protocol SwitcherPresenter: AnyObject {
    /// Shows `model` centered in `area` (global coordinates) at its content's size. Called
    /// again after cards go away, so the panel shrinks with them.
    func show(_ model: SwitcherModel, in area: CGRect)
    func hide()
    /// The panel's frame in global coordinates while it is shown.
    var visibleFrame: CGRect? { get }
}

/// The switcher in a clickable overlay panel, which never takes focus from the frontmost app.
@MainActor
final class OverlaySwitcherPresenter: SwitcherPresenter {
    private let host = OverlayHost<SwitcherView>(style: .interactive)

    func show(_ model: SwitcherModel, in area: CGRect) {
        host.show(SwitcherView(model: model), placement: .centered(in: area))
    }

    func hide() {
        host.hide()
    }

    var visibleFrame: CGRect? { host.isVisible ? host.frame : nil }
}
