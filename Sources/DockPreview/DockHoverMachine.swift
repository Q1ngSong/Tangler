import Contracts
import CoreGraphics
import Foundation

/// Decides when to look up Dock icons and when the preview opens and closes (design section
/// 4.4). Pure state: the controller feeds it pointer positions, lookup answers and the time,
/// and carries out the effects, so the delays are testable without a clock.
struct DockHoverMachine {
    enum Effect: Equatable {
        /// Ask which Dock icon is at this point, then report with `lookupFinished`.
        case lookUp(CGPoint)
        /// Start loading the app's windows and thumbnails: the pointer has rested half the delay.
        case prepare(DockItem)
        /// Open the app's preview, or replace the open one with it.
        case show(DockItem)
        case hide
    }

    /// Lookups are Accessibility round trips to the Dock; one runs at a time, this far apart.
    static let lookupInterval: TimeInterval = 0.05
    /// With a preview open, how long the pointer rests on another icon before the preview
    /// follows it there; just enough to pass over icons on the way.
    static let switchDelay: TimeInterval = 0.05

    var showDelay: TimeInterval
    var dismissDelay: TimeInterval

    private(set) var pointer: CGPoint?
    /// The icon under the pointer according to the latest lookup.
    private(set) var hovered: DockItem?
    /// The app whose preview is open or opening.
    private(set) var target: DockItem?
    /// Where the open preview is, once it is on screen.
    private(set) var panelFrame: CGRect?
    /// The app whose preview opens at `showDeadline`.
    private(set) var pending: DockItem?

    /// Loading waits for half the delay, so sweeping along the Dock loads nothing.
    private var prepareDeadline: TimeInterval?
    private var showDeadline: TimeInterval?
    private var hideDeadline: TimeInterval?
    private var queuedLookup: CGPoint?
    private var lookupInFlight = false
    private var lastLookup: TimeInterval?

    init(showDelay: TimeInterval, dismissDelay: TimeInterval) {
        self.showDelay = showDelay
        self.dismissDelay = dismissDelay
    }

    /// When `advance(to:)` next has something to do.
    var nextDeadline: TimeInterval? {
        var deadlines = [hideDeadline].compactMap { $0 }
        // A pending preview whose icon is being read again waits for that answer.
        if hovered != nil { deadlines += [prepareDeadline, showDeadline].compactMap { $0 } }
        if queuedLookup != nil, !lookupInFlight, let lastLookup { deadlines.append(lastLookup + Self.lookupInterval) }
        return deadlines.min()
    }

    mutating func pointerMoved(to point: CGPoint, nearDock: Bool, at now: TimeInterval) -> [Effect] {
        pointer = point
        if let panelFrame, panelFrame.contains(point) {
            hovered = nil
            cancelPending()
            hideDeadline = nil
            queuedLookup = nil
            return []
        }
        if let hovered, hovered.iconFrame.contains(point) { return [] }
        hovered = nil
        // Only the first departure sets the deadline, so constant movement cannot keep a preview open.
        if target != nil, hideDeadline == nil { hideDeadline = now + dismissDelay }
        guard nearDock else {
            cancelPending()
            queuedLookup = nil
            return []
        }
        // A pending preview survives until a lookup says the pointer left its icon: magnified
        // icons grow under the pointer, so the remembered frame goes stale on the same icon.
        queuedLookup = point
        return startLookup(at: now)
    }

    mutating func lookupFinished(_ item: DockItem?, at now: TimeInterval) -> [Effect] {
        lookupInFlight = false
        guard let pointer, panelFrame?.contains(pointer) != true else { return startLookup(at: now) }
        if let item, item.iconFrame.contains(pointer) {
            queuedLookup = nil
            return hover(item, at: now)
        }
        // With nothing newer queued the answer is about where the pointer still is: no icon to preview.
        if queuedLookup == nil { cancelPending() }
        return startLookup(at: now)
    }

    /// Any mouse button going down outside the preview closes it, and cancels the pending one:
    /// the Dock is about to act on the click. The pointer must then leave the icon before its
    /// preview opens again.
    mutating func mouseDown(at point: CGPoint) -> [Effect] {
        if let panelFrame, panelFrame.contains(point) { return [] }
        cancelPending()
        hideDeadline = nil
        guard target != nil else { return [] }
        target = nil
        panelFrame = nil
        return [.hide]
    }

    mutating func advance(to now: TimeInterval) -> [Effect] {
        var effects: [Effect] = []
        if let hideDeadline, now >= hideDeadline {
            self.hideDeadline = nil
            if target != nil {
                target = nil
                panelFrame = nil
                effects.append(.hide)
            }
        }
        return effects + fireDue(at: now) + startLookup(at: now)
    }

    /// The controller put the target's preview on screen at `frame`.
    mutating func presented(in frame: CGRect) {
        guard target != nil else { return }
        panelFrame = frame
    }

    /// The controller closed the preview itself, e.g. after a card was chosen.
    mutating func dismissed() {
        target = nil
        panelFrame = nil
        hideDeadline = nil
    }

    private mutating func hover(_ item: DockItem, at now: TimeInterval) -> [Effect] {
        hovered = item
        guard item.pid != nil else {
            // Not running, so nothing to preview; an open preview still closes on schedule.
            cancelPending()
            return []
        }
        hideDeadline = nil
        if target?.pid == item.pid {
            cancelPending()
            return []
        }
        if pending?.pid != item.pid {
            if target != nil {
                // A preview is open: it follows the pointer along the Dock, loading as it opens.
                prepareDeadline = nil
                showDeadline = now + Self.switchDelay
            } else {
                prepareDeadline = now + showDelay / 2
                showDeadline = now + showDelay
            }
        }
        pending = item
        return fireDue(at: now)
    }

    private mutating func fireDue(at now: TimeInterval) -> [Effect] {
        guard let pending, hovered?.pid == pending.pid else { return [] }
        if let showDeadline, now >= showDeadline {
            cancelPending()
            target = pending
            return [.show(pending)]
        }
        if let prepareDeadline, now >= prepareDeadline {
            self.prepareDeadline = nil
            return [.prepare(pending)]
        }
        return []
    }

    private mutating func cancelPending() {
        pending = nil
        prepareDeadline = nil
        showDeadline = nil
    }

    private mutating func startLookup(at now: TimeInterval) -> [Effect] {
        guard let point = queuedLookup, !lookupInFlight else { return [] }
        if let lastLookup, now < lastLookup + Self.lookupInterval { return [] }
        queuedLookup = nil
        lookupInFlight = true
        lastLookup = now
        return [.lookUp(point)]
    }
}
