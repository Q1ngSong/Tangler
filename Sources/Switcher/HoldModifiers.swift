import AppKit
import Contracts

/// The modifiers that keep the switcher open, like Command for ⌘Tab: letting go of one
/// chooses the selected window. Shift only reverses, so it does not count unless the
/// shortcut has nothing else; a shortcut without modifiers leaves the switcher open until
/// Return, Esc or a click.
struct HoldModifiers: Equatable {
    let required: Modifiers

    init(chord: KeyChord?) {
        let modifiers = chord?.modifiers.subtracting(.function) ?? []
        let withoutShift = modifiers.subtracting(.shift)
        required = withoutShift.isEmpty ? modifiers : withoutShift
    }

    func isReleased(in current: Modifiers) -> Bool {
        !required.isEmpty && !current.isSuperset(of: required)
    }

    static func modifiers(from flags: NSEvent.ModifierFlags) -> Modifiers {
        var modifiers: Modifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.function) { modifiers.insert(.function) }
        return modifiers
    }
}
