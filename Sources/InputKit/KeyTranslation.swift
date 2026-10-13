import Contracts
import CoreGraphics
import CoreKit

extension Key {
    /// The shared name from `KeyCodes`. Keys missing from that table get "#<code>", so a
    /// capture still learns that something was pressed.
    init(keyCode: UInt16) {
        self.init(rawValue: KeyCodes.name(for: keyCode) ?? "#\(keyCode)")
    }
}

extension Modifiers {
    /// The device-independent modifier flags. Caps Lock is not a modifier here.
    init(eventFlags flags: CGEventFlags) {
        var modifiers: Modifiers = []
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskSecondaryFn) { modifiers.insert(.function) }
        self = modifiers
    }

    /// macOS sets fn on arrow and function keys whether or not fn is held, so key presses
    /// and shortcut matching leave it out.
    var ignoringFunction: Modifiers { subtracting(.function) }
}
