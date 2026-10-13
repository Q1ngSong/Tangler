import CoreKit
/// What a plain click on the icon of the app already in front does (design section 4.4).
/// Clicks on other apps' icons always keep the Dock's own behaviour.
public enum DockClickBehavior: String, Codable, CaseIterable, Sendable {
    case systemDefault
    /// Minimizes the app's focused window, and only that window.
    case minimizeWindow
    case hideApplication

    var title: String {
        switch self {
        case .systemDefault: return L10n.text("dockpreview.system.default")
        case .minimizeWindow: return L10n.text("dockpreview.minimize.focused.window")
        case .hideApplication: return L10n.text("dockpreview.hide.application")
        }
    }
}
