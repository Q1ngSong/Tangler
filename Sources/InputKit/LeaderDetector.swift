import Contracts
import CoreGraphics
import CoreKit
import Foundation

/// Recognizes the leader trigger (design section 4.2). Pure state: the router feeds it
/// modifier changes, key presses and interruptions.
struct LeaderDetector {
    var trigger: LeaderTrigger? {
        didSet { reset() }
    }

    /// Right Command went down on its own and nothing has happened since: letting it go is a tap.
    private var isTapping = false
    /// With `.holdRightCommand`: right Command is down and is the leader key, not ⌘.
    private(set) var isHolding = false

    init(trigger: LeaderTrigger? = nil) {
        self.trigger = trigger
    }

    /// Feeds a modifier key change. Returns true when it fires the trigger: the end of a
    /// right-Command tap, or right Command going down on its own with the hold trigger.
    mutating func modifierChanged(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        switch trigger {
        case .tapRightCommand?: return tapChanged(keyCode: keyCode, flags: flags)
        case .holdRightCommand?: return holdChanged(keyCode: keyCode, flags: flags)
        case .chord?, nil: return false
        }
    }

    /// A key, click or scroll while right Command is down means it is in use as a modifier:
    /// no tap. A hold goes on, since keys are what it is for.
    mutating func interrupt() {
        isTapping = false
    }

    /// Every key press carries the modifier state, so a hold whose release went missing, e.g.
    /// while the system had the tap disabled, ends with the first key pressed without it.
    mutating func keyPressed(flags: CGEventFlags) {
        if isHolding && !Self.isRightCommandDown(flags) { isHolding = false }
    }

    /// Forgets a tap or hold in progress, e.g. after events went missing.
    mutating func reset() {
        isTapping = false
        isHolding = false
    }

    /// Whether a key press is the `.chord` trigger.
    func isChord(_ key: Key, modifiers: Modifiers) -> Bool {
        guard case .chord(let chord) = trigger else { return false }
        return chord.key == key && chord.modifiers.ignoringFunction == modifiers.ignoringFunction
    }

    private mutating func tapChanged(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        guard keyCode == KeyCodes.rightCommand else {
            isTapping = false
            return false
        }
        if Self.isRightCommandDown(flags) {
            isTapping = Self.isOnlyRightCommand(flags)
            return false
        }
        defer { isTapping = false }
        return isTapping
    }

    private mutating func holdChanged(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        // Other modifiers may come and go while it is held; only its own release ends a hold.
        guard keyCode == KeyCodes.rightCommand else { return false }
        guard Self.isRightCommandDown(flags) else {
            isHolding = false
            return false
        }
        guard !isHolding, Self.isOnlyRightCommand(flags) else { return false }
        isHolding = true
        return true
    }

    // Per-side device bits from IOLLEvent.h. Synthesized events may carry none of them,
    // and then only the device-independent Command flag tells press from release.
    private static let deviceBits: UInt64 = 0x207F
    private static let rightCommandBit: UInt64 = 0x10
    private static let leftCommandBit: UInt64 = 0x08

    private static func isRightCommandDown(_ flags: CGEventFlags) -> Bool {
        flags.rawValue & deviceBits == 0 ? flags.contains(.maskCommand) : flags.rawValue & rightCommandBit != 0
    }

    private static func isOnlyRightCommand(_ flags: CGEventFlags) -> Bool {
        Modifiers(eventFlags: flags).ignoringFunction == .command && flags.rawValue & leftCommandBit == 0
    }
}
