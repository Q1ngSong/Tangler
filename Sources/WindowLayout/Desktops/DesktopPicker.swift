import CoreKit
import Contracts

/// Which desktop a "切到…桌面" command asks for.
enum DesktopChoice: Equatable, Sendable {
    case previous, next
    /// The digit typed after D; 0 stands for the tenth desktop.
    case number(Int?)
}

enum DesktopPick: Equatable, Sendable {
    case go(SpaceID)
    /// The requested desktop is already showing.
    case stay
    /// Why there is nowhere to go, shown to the user.
    case impossible(String)
}

/// Finds desktops among the ordinary desktops of a display, in the order the Space list gives
/// them. Full-screen Spaces are never counted.
enum DesktopPicker {
    static var notOnADesktop: String { L10n.text("windowlayout.the.current.space.is.not.a.regular") }

    /// The display's ordinary desktops; with shared Spaces, where the list names one display
    /// only, the desktops of the display that has the current one.
    static func desktops(on display: DisplayID, among spaces: [SpaceInfo]) -> [SpaceInfo] {
        let ordinary = spaces.filter { !$0.isFullscreen }
        if spaces.contains(where: { $0.displayID == display }) { return ordinary.filter { $0.displayID == display } }
        guard let shared = ordinary.first(where: \.isCurrent)?.displayID else { return [] }
        return ordinary.filter { $0.displayID == shared }
    }

    /// The desktop showing on the display; nil while a full-screen Space covers it.
    static func current(on display: DisplayID, among spaces: [SpaceInfo]) -> SpaceInfo? {
        desktops(on: display, among: spaces).first(where: \.isCurrent)
    }

    static func pick(_ choice: DesktopChoice, on display: DisplayID, among spaces: [SpaceInfo]) -> DesktopPick {
        let row = desktops(on: display, among: spaces)
        let target: SpaceInfo
        switch choice {
        case .previous:
            guard let position = row.firstIndex(where: \.isCurrent) else { return .impossible(notOnADesktop) }
            guard position > 0 else { return .impossible(L10n.text("windowlayout.already.on.the.leftmost.desktop")) }
            target = row[position - 1]
        case .next:
            guard let position = row.firstIndex(where: \.isCurrent) else { return .impossible(notOnADesktop) }
            guard position < row.count - 1 else { return .impossible(L10n.text("windowlayout.already.on.the.rightmost.desktop")) }
            target = row[position + 1]
        case .number(let digit):
            guard let digit else { return .impossible(L10n.text("windowlayout.a.desktop.number.is.required")) }
            let number = digit == 0 ? 10 : digit
            guard row.indices.contains(number - 1) else {
                return .impossible(L10n.text("windowlayout.desktop.does.not.exist.total", String(describing: (number)), String(describing: (row.count))))
            }
            target = row[number - 1]
        }
        return target.isCurrent ? .stay : .go(target.id)
    }
}
