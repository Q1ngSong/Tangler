import Contracts

/// What a key press does while the switcher is open.
enum SwitcherAction: Equatable {
    case forward, backward, choose, cancel
}

/// Keys the switcher's capture receives. Modifiers are mostly ignored: the shortcut's own
/// modifiers are still held while the user steps through the windows.
struct SwitcherKeys: Equatable {
    /// The key of the shortcut that opened the switcher; pressing it again steps forward.
    var trigger: Key

    /// The keypad's Enter key, which has no name in `CoreKit.KeyCodes`.
    static let keypadEnter: Key = "#76"

    func action(for press: KeyPress) -> SwitcherAction? {
        let key = press.key
        if key == .tab || key == trigger {
            return press.modifiers.contains(.shift) ? .backward : .forward
        }
        switch key {
        // As in the system switcher, ⌘` steps back through a ⌘Tab list.
        case .backtick, .left, .up: return .backward
        case .right, .down: return .forward
        case .returnKey, Self.keypadEnter: return .choose
        case .escape: return .cancel
        default: return nil
        }
    }
}
