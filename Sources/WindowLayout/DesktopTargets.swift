import CoreKit
import Contracts

/// Which desktop a "移到…桌面" command asks for.
enum DesktopStep: Equatable, Sendable {
    case left, right
    /// The digit typed after S; 0 stands for the tenth desktop.
    case number(Int?)
}

enum DesktopMove: Equatable, Sendable {
    case move(SpaceID)
    /// The window is already on the requested desktop.
    case stay
    /// Why there is nowhere to go, shown to the user.
    case impossible(String)
}

/// Finds the target desktop among the ordinary desktops of the window's display, numbered
/// like Mission Control's "桌面 N". Full-screen Spaces are never targets.
enum DesktopTargets {
    static func resolve(_ step: DesktopStep, for window: WindowInfo, among spaces: [SpaceInfo]) -> DesktopMove {
        let desktops = spaces.filter { !$0.isFullscreen }
        guard let current = currentDesktop(of: window, in: desktops) else {
            return .impossible(L10n.text("windowlayout.cannot.determine.this.window.s.desktop"))
        }
        let row = desktops.filter { $0.displayID == current.displayID }.sorted { $0.index < $1.index }
        let target: SpaceInfo?
        switch step {
        case .left:
            target = row.last { $0.index < current.index }
            if target == nil { return .impossible(L10n.text("windowlayout.no.desktop.to.the.left")) }
        case .right:
            target = row.first { $0.index > current.index }
            if target == nil { return .impossible(L10n.text("windowlayout.no.desktop.to.the.right")) }
        case .number(let digit):
            guard let digit else { return .impossible(L10n.text("windowlayout.a.desktop.number.is.required")) }
            let number = digit == 0 ? 10 : digit
            target = row.first { $0.index == number }
            if target == nil { return .impossible(L10n.text("windowlayout.there.is.no.desktop", String(describing: (number)))) }
        }
        guard let target, target.id != current.id else { return .stay }
        return .move(target.id)
    }

    /// The desktop the window reports; without one, the desktop showing on the window's
    /// display, or with shared Spaces the only current one.
    private static func currentDesktop(of window: WindowInfo, in desktops: [SpaceInfo]) -> SpaceInfo? {
        if let own = window.spaceIDs.lazy.compactMap({ id in desktops.first { $0.id == id } }).first { return own }
        return desktops.first { $0.isCurrent && $0.displayID == window.displayID } ?? desktops.first(where: \.isCurrent)
    }
}
