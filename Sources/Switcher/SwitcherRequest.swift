import Contracts

/// Which windows a switcher lists.
enum SwitcherKind: Equatable {
    /// Every window on every display and, when the system allows it, on every Space.
    case allWindows
    /// The windows of the focused window's application.
    case appWindows

    /// The key that steps forward when the shortcut is unknown.
    var defaultTrigger: Key { self == .allWindows ? .tab : .backtick }
}

/// What one press of a switcher shortcut asks for.
struct SwitcherRequest: Equatable {
    var kind: SwitcherKind
    /// Starts from the far end of the list, as ⇧⌘Tab does.
    var reverse = false
    /// The shortcut as the user has it now. Its key steps forward; letting go of its
    /// modifiers chooses the selected window.
    var chord: KeyChord?
}
