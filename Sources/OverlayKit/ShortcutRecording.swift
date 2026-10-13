import AppKit
import Contracts
import CoreKit

/// What a key press means to the shortcut recorder.
enum ShortcutRecording {
    enum Outcome: Equatable, Sendable {
        case record(KeyChord)
        /// Esc alone stops recording and keeps the current chord.
        case cancel
        /// Delete or Forward Delete alone removes the chord.
        case clear
        /// Recording continues; the text says why the press was refused.
        case reject(String)
    }

    /// Not in `KeyCodes`, whose names are the keys a chord can use.
    static let forwardDeleteKeyCode: UInt16 = 0x75

    static func outcome(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Outcome {
        let modifiers = modifiers(from: modifierFlags)
        let name = KeyCodes.name(for: keyCode)
        if modifiers.isEmpty {
            if name == Key.escape.rawValue { return .cancel }
            if name == "delete" || keyCode == forwardDeleteKeyCode { return .clear }
        }
        guard let name else { return .reject(L10n.text("overlaykit.this.key.is.not.supported")) }
        // Shift alone would swallow capital letters everywhere.
        guard !modifiers.isDisjoint(with: [.command, .option, .control]) else {
            return .reject(L10n.text("overlaykit.hold.or.as.well"))
        }
        return .record(KeyChord(Key(rawValue: name), modifiers: modifiers))
    }

    /// ⌃⌥⇧⌘ only. AppKit sets the fn and numeric-pad flags for arrow keys, and InputKit
    /// ignores Caps Lock and fn when matching, so none of them may end up in a chord.
    static func modifiers(from flags: NSEvent.ModifierFlags) -> Modifiers {
        var modifiers: Modifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return modifiers
    }
}
