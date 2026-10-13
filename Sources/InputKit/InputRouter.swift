import Contracts
import CoreGraphics
import Foundation

/// What to do with one event: whether the frontmost app loses it, what to report, and
/// which capture receives it.
struct Routing: Equatable {
    var swallow = false
    var events: [InputEvent] = []
    var delivery: KeyDelivery?
}

struct KeyDelivery: Equatable {
    var captureID: Int
    var press: KeyPress
}

/// Decides what every event means. Pure state: the tap thread calls it under a lock and
/// tests call it directly with synthetic events.
///
/// Key presses go, in order, to the leader chord, the newest capture, the keys waiting for
/// leader mode, then the shortcuts; a capture comes before shortcuts so an open switcher
/// receives the next ⌘Tab itself. While right Command is held as the leader key, presses lose
/// its ⌘ and never reach the app. Modifier, mouse and scroll events are reported and never
/// swallowed.
struct InputRouter {
    /// How long after the leader fires keys wait for leader mode's capture. Leader mode starts
    /// one at once, so this only has to cover a busy moment.
    static let leaderKeyWait: TimeInterval = 0.5

    var leader = LeaderDetector()
    var shortcuts = ShortcutTable()
    /// Checked when a right-Command tap completes. While a password field holds the
    /// keyboard, captures cannot see keys, so the leader must not start.
    var isSecureInputActive: () -> Bool = { false }
    /// While true, shortcuts and the leader trigger are ignored and their keys reach the app,
    /// so the settings page can record any chord. Captures are unaffected.
    var shortcutsSuspended = false {
        didSet { leader.reset() }
    }

    /// Pointer moves inside it are reported but kept from apps (`InputService.setMouseMoveShield`).
    var mouseMoveShield: CGRect?
    /// Capture ids, newest last.
    private(set) var captures: [Int] = []
    /// When the leader fired with no capture open, so leader mode's capture is on its way;
    /// keys typed meanwhile wait for it instead of reaching the app.
    private var leaderFiredAt: TimeInterval?
    private var waitingKeys: [KeyPress] = []
    /// Keys whose press was swallowed; their repeats and release are swallowed too, so the
    /// app never sees half a key stroke.
    private var swallowedKeys: Set<UInt16> = []
    private var lastModifiers: Modifiers?

    /// Returns the keys typed since the leader fired, which the new capture receives first.
    mutating func beginCapture(_ id: Int, at time: TimeInterval) -> [KeyPress] {
        captures.append(id)
        defer {
            leaderFiredAt = nil
            waitingKeys = []
        }
        return isWaitingForLeaderMode(at: time) ? waitingKeys : []
    }

    mutating func endCapture(_ id: Int) {
        captures.removeAll { $0 == id }
    }

    /// Forgets state that missed events may have made stale, e.g. after the system
    /// disabled the tap. Captures, shortcuts and the trigger stay.
    mutating func reset() {
        leader.reset()
        swallowedKeys.removeAll()
        lastModifiers = nil
        leaderFiredAt = nil
        waitingKeys = []
    }

    mutating func route(_ event: RawInputEvent, at time: TimeInterval) -> Routing {
        switch event.kind {
        case .keyDown(let keyCode, let isRepeat):
            return keyDown(keyCode, isRepeat: isRepeat, flags: event.flags, at: time)
        case .keyUp(let keyCode):
            leader.interrupt()
            return Routing(swallow: swallowedKeys.remove(keyCode) != nil)
        case .flagsChanged(let keyCode):
            return modifiersChanged(keyCode, flags: event.flags, at: time)
        case .mouseDown(let button):
            leader.interrupt()
            return Routing(events: [.mouseDown(mouseEvent(event, button))])
        case .mouseDragged(let button):
            return Routing(events: [.mouseDragged(mouseEvent(event, button))])
        case .mouseUp(let button):
            return Routing(events: [.mouseUp(mouseEvent(event, button))])
        case .mouseMoved:
            return Routing(swallow: mouseMoveShield?.contains(event.location) == true,
                           events: [.mouseMoved(event.location)])
        case .scroll(let delta, let isContinuous, let isMomentum):
            leader.interrupt()
            // Momentum keeps scrolling after the fingers lift; consumers step through
            // items with scrolls and have no way to tell those events apart.
            guard !isMomentum, delta != .zero else { return Routing() }
            return Routing(events: [.scroll(ScrollEvent(location: event.location, delta: delta,
                                                        isContinuous: isContinuous))])
        }
    }

    private mutating func keyDown(_ keyCode: UInt16, isRepeat: Bool, flags: CGEventFlags,
                                  at time: TimeInterval) -> Routing {
        leader.interrupt()
        leader.keyPressed(flags: flags)
        // A new press means the previous one ended, even if its release never arrived.
        if !isRepeat { swallowedKeys.remove(keyCode) }
        let key = Key(keyCode: keyCode)
        let modifiers = Modifiers(eventFlags: flags).ignoringFunction
        // Held as the leader key, right Command is not ⌘: leader mode sees F, not ⌘F.
        let press = KeyPress(key, modifiers: leader.isHolding ? modifiers.subtracting(.command) : modifiers,
                             isRepeat: isRepeat)
        var routing = Routing(swallow: true)
        if !shortcutsSuspended, leader.isChord(key, modifiers: modifiers) {
            if !isRepeat {
                routing.events = [.leaderTriggered]
                leaderFired(at: time)
            }
        } else if let capture = captures.last {
            routing.delivery = KeyDelivery(captureID: capture, press: press)
        } else if isWaitingForLeaderMode(at: time) {
            waitingKeys.append(press)
        } else if leader.isHolding {
            // Leader mode has ended while the key is still held, e.g. after opening the palette.
            // The key still belongs to Tangler, so its keys go nowhere rather than to the app as ⌘.
        } else if !shortcutsSuspended, let id = shortcuts.owner(of: key, modifiers: modifiers) {
            if !isRepeat { routing.events = [.shortcut(id: id)] }
        } else {
            routing.swallow = isRepeat && swallowedKeys.contains(keyCode)
        }
        if routing.swallow && !isRepeat { swallowedKeys.insert(keyCode) }
        return routing
    }

    private mutating func modifiersChanged(_ keyCode: UInt16, flags: CGEventFlags, at time: TimeInterval) -> Routing {
        var routing = Routing()
        let modifiers = Modifiers(eventFlags: flags)
        if modifiers != lastModifiers {
            lastModifiers = modifiers
            routing.events.append(.modifiersChanged(modifiers))
        }
        if leader.modifierChanged(keyCode: keyCode, flags: flags) {
            if shortcutsSuspended || isSecureInputActive() {
                // A hold would swallow keys that leader mode never gets.
                leader.reset()
            } else {
                routing.events.append(.leaderTriggered)
                leaderFired(at: time)
            }
        }
        return routing
    }

    /// Without a capture open, leader mode is about to start one: keys wait for it. With one
    /// open, the trigger turns leader mode off, or another capture holds the keyboard.
    private mutating func leaderFired(at time: TimeInterval) {
        leaderFiredAt = captures.isEmpty ? time : nil
        waitingKeys = []
    }

    private func isWaitingForLeaderMode(at time: TimeInterval) -> Bool {
        guard let leaderFiredAt else { return false }
        return time - leaderFiredAt <= Self.leaderKeyWait
    }

    private func mouseEvent(_ event: RawInputEvent, _ button: MouseButton) -> MouseEvent {
        MouseEvent(location: event.location, button: button, modifiers: Modifiers(eventFlags: event.flags))
    }
}
