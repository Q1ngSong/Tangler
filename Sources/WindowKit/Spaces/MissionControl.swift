import CoreKit
import Contracts
import CoreGraphics
import Foundation

/// One desktop's button in Mission Control's Spaces bar, as the Dock reports it.
struct SpaceButton: Equatable {
    var title: String
    var frame: CGRect
    /// Accessibility action names, e.g. "AXPress".
    var actions: [String]
}

/// Adds, shows and removes desktops by operating Mission Control through the Dock's
/// accessibility tree (workspaces design 7.2–7.5). An accessibility action that reports success
/// proves nothing: every step is confirmed from the window server's Space list. One operation
/// runs at a time, never while the screen is locked, the user has Mission Control open, or the
/// Dock does not say whether it is. Cancellation is never looked at: an operation runs to its end
/// whether its task is cancelled before it starts or on the way, so Mission Control is closed
/// again and a desktop added on the way is removed, or what could not be done is reported. A
/// caller that cancels decides so before calling, and its rollback, which runs in the cancelled
/// task, works like any other call. Nothing is toggled while the Dock does not say whether
/// Mission Control shows.
///
/// Known limit: an operation cannot be abandoned once it has started, and its waits are counted
/// in checks, not in time. A Dock that stops answering holds the operation, and with it every
/// other desktop operation, for as long as those checks take to time out.
final class MissionControl: @unchecked Sendable {
    static let pressAction = "AXPress"
    static let removeAction = "AXRemoveDesktop"
    /// Reported when a desktop this class added is still there at the end. It gives no number:
    /// the one read when the desktop appeared is stale once another desktop has been removed.
    static var leftBehind: String { L10n.text("windowkit.the.temporary.desktop.could.not.be.removed") }
    /// Reported when an operation that may have left Mission Control showing ends without
    /// learning whether it went away.
    static var stateUnknown: String { L10n.text("windowkit.could.not.read.mission.control.s.state") }
    /// Reported when an operation ends with Mission Control still showing after telling it to go.
    static var stillShowing: String { L10n.text("windowkit.mission.control.did.not.close") }

    struct Hooks {
        var isAuthorized: () -> Bool
        var isScreenLocked: () -> Bool
        /// Every Space in the window server's order, full-screen ones included. An empty list
        /// means the Spaces could not be read.
        var spaces: () async -> [SpaceInfo]
        /// Whether Mission Control is showing; nil when the Dock did not say. No answer is never
        /// "closed": the flow asks again, and toggles nothing in the meantime.
        var isOpen: () async -> Bool?
        /// Opens Mission Control when it is closed and closes it when it is open.
        var toggle: @MainActor () -> Void
        /// The Spaces bar's buttons on a display, left to right; nil while they cannot be read.
        var buttons: (DisplayID) async -> [SpaceButton]?
        /// Presses "add desktop" on a display. False means only that the button was not found and
        /// nothing was sent; true does not say a desktop appeared.
        var pressAdd: (DisplayID) async -> Bool
        /// Performs an action on the button at a position in a bar of `count` buttons. False means
        /// only that nothing was sent: the button was not found, or the bar no longer has `count`
        /// buttons and the position may be another Space's by now. True does not say the action
        /// took effect.
        var perform: (_ action: String, _ position: Int, _ count: Int, DisplayID) async -> Bool
        /// Ordinary windows that are on this Space and on no other; nil when that cannot be read.
        var windowCount: (SpaceID) -> Int?
        /// Waits between checks. It has to wait even when the task is cancelled: an operation
        /// that has started runs to its end, and a pause that returned at once, as `Task.sleep`
        /// does in a cancelled task, would use its waits up before the Dock could answer.
        var pause: () async -> Void
        /// Something the user should know that no result carries, such as a desktop left behind.
        var report: (String) -> Void
        /// Full cleanup inventory, including hidden/minimized and shared windows. Separate from
        /// `windowCount`, whose narrower rule is used for our temporary desktops.
        var isEmpty: (SpaceID) async -> Bool? = { _ in nil }
    }

    private enum Deletion {
        case gone
        /// The request was sent and the desktop is still there.
        case ignored
        /// The desktop's button could not be told apart; nothing was sent.
        case unreadable
        case protected
    }

    /// The Spaces bar at rest: its buttons, and the display's Spaces they stand for, in order.
    private typealias Bar = (buttons: [SpaceButton], spaces: [SpaceInfo])

    /// What one operation remembers from step to step. It lives as long as the operation.
    private final class Run {
        /// Mission Control may be showing because of this operation: it sent the toggle that
        /// opens it, or went on with one it found showing. Before that, closing Mission Control
        /// is none of its business.
        var mayBeShowing = false
    }

    private let unavailableReason: () -> String?
    private let pollLimit: Int
    private let hooks: Hooks
    private let gate: DesktopGate

    /// `unavailableReason` is nil when desktops can be managed. Each wait gives up after
    /// `pollLimit` pauses: at least 2 seconds with the live 40 ms pause, and longer by the time
    /// the checks between the pauses take.
    init(unavailableReason: @autoclosure @escaping () -> String?, gate: DesktopGate = DesktopGate(), pollLimit: Int = 50, hooks: Hooks) {
        self.unavailableReason = unavailableReason
        self.gate = gate
        self.pollLimit = pollLimit
        self.hooks = hooks
    }

    /// Adds a desktop at the end of `display`'s list. With `switching` it also goes there; when
    /// that part fails the desktop still exists and comes back with `isCurrent` false.
    func add(on display: DisplayID, switching: Bool) async -> Result<SpaceInfo, WindowError> {
        await exclusively { await self.adding(on: display, switching: switching, in: $0) }
    }

    /// Goes to an ordinary desktop that has no window to focus.
    func show(_ space: SpaceID) async -> Result<Void, WindowError> {
        await exclusively { await self.showing(space, in: $0) }
    }

    /// Removes an ordinary desktop; macOS moves its windows to a neighbouring one.
    func remove(_ space: SpaceID) async -> Result<Void, WindowError> {
        await removal(of: space).result
    }

    /// `remove`, also saying whether it got as far as asking for Mission Control. Before that
    /// nothing was sent, so no desktop and no window can have changed; from there on a removal may
    /// land whatever the result says.
    func removal(of space: SpaceID, onlyIfEmpty: Bool = false) async -> (result: Result<Void, WindowError>, opened: Bool) {
        let run = Run()
        let result = await exclusively(run) { await self.removing(space, onlyIfEmpty: onlyIfEmpty, in: $0) }
        return (result, run.mayBeShowing)
    }

    /// Whether `button`, one of `bar`'s, can be `space`'s: the digits in its title must be the
    /// desktop's number. The bar numbers its desktops by where their buttons stand in it, so this
    /// notices a full-screen Space's button that stands elsewhere in the bar than its Space does
    /// in the list, and a bar that numbers differently altogether. It cannot notice two desktops
    /// whose buttons are swapped. A title without digits passes only in a bar where no title has
    /// any, which gives nothing to compare; beside numbered titles it is a full-screen
    /// application's, and must not stand in for a desktop.
    static func names(_ button: SpaceButton, in bar: [SpaceButton], _ space: SpaceInfo) -> Bool {
        let digits = button.title.filter(\.isNumber)
        guard digits.isEmpty else { return digits == String(space.index) }
        return !bar.contains { $0.title.contains(where: \.isNumber) }
    }

    /// Whether the button at `index` stands for the Space at `index`. A desktop that was just added
    /// has an empty title for a while, also in the next Mission Control session (measured on
    /// 26.6.1). Such a button is taken for its desktop when every other ordinary desktop's button
    /// carries its own number, which shows the bar and the list are in step.
    static func names(buttonAt index: Int, of buttons: [SpaceButton], for spaces: [SpaceInfo]) -> Bool {
        if names(buttons[index], in: buttons, spaces[index]) { return true }
        guard buttons[index].title.isEmpty, !spaces[index].isFullscreen else { return false }
        let others = zip(buttons, spaces).enumerated().filter { $0.offset != index && !$0.element.1.isFullscreen }
        return !others.isEmpty && others.allSatisfy { other in
            other.element.0.title.contains(where: \.isNumber) && names(other.element.0, in: buttons, other.element.1)
        }
    }

    // MARK: Operations

    private func exclusively<Value>(_ run: Run = Run(),
                                    _ body: (Run) async -> Result<Value, WindowError>) async -> Result<Value, WindowError> {
        if let unavailableReason = unavailableReason() { return .failure(.unsupported(unavailableReason)) }
        guard hooks.isAuthorized() else { return .failure(.notAuthorized) }
        guard !hooks.isScreenLocked() else { return .failure(.rejected(L10n.text("windowkit.the.screen.is.locked"))) }
        guard gate.enter() else { return .failure(.rejected(L10n.text("windowkit.the.previous.desktop.operation.has.not.finished"))) }
        defer { gate.leave() }
        guard let showing = await hooks.isOpen() else { return .failure(.rejected(L10n.text("windowkit.could.not.read.mission.control.s.state.missioncontrol"))) }
        guard !showing else { return .failure(.rejected(L10n.text("windowkit.mission.control.is.open.close.it.first"))) }
        let result = await body(run)
        // How the operation leaves Mission Control is said here, once: a close on the way may
        // fail and a later one still succeed.
        if let problem = await close(run) { hooks.report(problem) }
        return result
    }

    private func adding(on display: DisplayID, switching: Bool, in run: Run) async -> Result<SpaceInfo, WindowError> {
        // Said before Mission Control opens: it would open and close again for nothing.
        let all = await hooks.spaces()
        guard !all.isEmpty else { return .failure(.rejected(L10n.text("windowkit.could.not.read.the.desktop.list"))) }
        guard all.contains(where: { $0.displayID == display }) else { return .failure(.rejected(L10n.text("windowkit.this.display.has.no.desktops"))) }
        guard await open(run) else { return .failure(.rejected(L10n.text("windowkit.mission.control.did.not.open"))) }
        guard let created = await addDesktop(on: display) else {
            return .failure(.rejected(L10n.text("windowkit.no.new.desktop.appeared.mission.control.may")))
        }
        guard switching else { return .success(created) }
        var added = created
        if await press(created.id, on: display) { added.isCurrent = true }
        return .success(added)
    }

    private func showing(_ space: SpaceID, in run: Run) async -> Result<Void, WindowError> {
        guard let target = await hooks.spaces().first(where: { $0.id == space && !$0.isFullscreen }) else {
            return .failure(.rejected(L10n.text("windowkit.the.target.desktop.does.not.exist.or")))
        }
        if target.isCurrent { return .success(()) }
        let display = target.displayID
        guard await open(run) else { return .failure(.rejected(L10n.text("windowkit.mission.control.did.not.open"))) }
        guard await position(of: space, on: display, offering: nil) != nil else {
            return .failure(.rejected(L10n.text("windowkit.mission.control.has.changed.the.target.desktop")))
        }
        // A button only switches desktops after one was added in the same session (design 2.5
        // item 3), so a temporary desktop is added, and removed in a session of its own.
        guard let temporary = await addDesktop(on: display) else {
            return .failure(.rejected(L10n.text("windowkit.no.new.desktop.appeared.mission.control.may")))
        }
        let switched = await press(space, on: display)
        await close(run)
        await discard(temporary, on: display, in: run)
        // A switch that was confirmed stands, whatever the Space list says after the tidying up.
        // One that was not is asked about once more: it can land after the wait for it ran out.
        if switched { return .success(()) }
        return await isCurrent(space) ? .success(()) : .failure(.rejected(L10n.text("windowkit.could.not.switch.to.the.target.desktop")))
    }

    private func removing(_ space: SpaceID, onlyIfEmpty: Bool, in run: Run) async -> Result<Void, WindowError> {
        let all = await hooks.spaces()
        guard let target = all.first(where: { $0.id == space && !$0.isFullscreen }) else {
            return .failure(.rejected(L10n.text("windowkit.the.target.desktop.does.not.exist.or")))
        }
        guard all.filter({ $0.displayID == target.displayID && !$0.isFullscreen }).count > 1 else {
            return .failure(.rejected(L10n.text("windowkit.the.last.desktop.on.this.display.cannot")))
        }
        if onlyIfEmpty, await hooks.isEmpty(space) != true {
            return .failure(.rejected(L10n.text("windowkit.the.desktop.has.windows.or.could.not")))
        }
        guard await open(run) else { return .failure(.rejected(L10n.text("windowkit.mission.control.did.not.open"))) }
        switch await delete(space, on: target.displayID, onlyIfEmpty: onlyIfEmpty) {
        case .gone: return .success(())
        case .protected: return .failure(.rejected(L10n.text("windowkit.the.desktop.has.windows.could.not.be")))
        case .ignored: return .failure(.rejected(L10n.text("windowkit.a.removal.request.was.sent.but.the")))
        case .unreadable: return .failure(.rejected(L10n.text("windowkit.mission.control.has.changed.the.desktop.to")))
        }
    }

    // MARK: Steps

    /// Presses "add desktop" and waits for the new desktop to show in the Space list.
    private func addDesktop(on display: DisplayID) async -> SpaceInfo? {
        let before = Set(await spaces(on: display).map(\.id))
        // Against a list that could not be read, every desktop would look new.
        guard !before.isEmpty, await hooks.pressAdd(display) else { return nil }
        var created: SpaceInfo?
        _ = await wait {
            created = await self.spaces(on: display).first { !before.contains($0.id) && !$0.isFullscreen }
            return created != nil
        }
        return created
    }

    /// Presses a desktop's button; true once the Space list shows that desktop as the current
    /// one. Only works after a desktop was added in this session and before any was removed
    /// (design 2.5 item 3). False does not say the switch will not land later.
    private func press(_ space: SpaceID, on display: DisplayID) async -> Bool {
        guard let place = await position(of: space, on: display, offering: Self.removeAction),
              await hooks.perform(Self.pressAction, place.index, place.count, display),
              await wait(until: { await self.isCurrent(space) }) else { return false }
        // Mission Control leaves by itself after a switch; let it, before anything toggles it.
        _ = await wait { await self.hooks.isOpen() == false }
        return true
    }

    /// `AXRemoveDesktop` on the desktop's button. A collapsed bar took it when measured although it
    /// does not list the action; if it is ignored, a temporary desktop expands the bar first.
    private func delete(_ space: SpaceID, on display: DisplayID, onlyIfEmpty: Bool = false) async -> Deletion {
        let first = await deleteOnce(space, on: display, offering: nil, onlyIfEmpty: onlyIfEmpty)
        guard first == .ignored, let temporary = await addDesktop(on: display) else { return first }
        let second = await deleteOnce(space, on: display, offering: Self.removeAction, onlyIfEmpty: onlyIfEmpty)
        var cleared = false
        if hooks.windowCount(temporary.id) == 0 {
            cleared = await deleteOnce(temporary.id, on: display, offering: Self.removeAction) == .gone
        }
        if !cleared { hooks.report(Self.leftBehind) }
        return second
    }

    private func deleteOnce(_ space: SpaceID, on display: DisplayID, offering action: String?,
                            onlyIfEmpty: Bool = false) async -> Deletion {
        // A window may arrive while Mission Control animates or retries. Check after the bar
        // settles, and confirm its index is still the target's after the inventory read.
        guard let place = await position(of: space, on: display, offering: action) else {
            return await isGone(space, on: display) ? .gone : .unreadable
        }
        if onlyIfEmpty {
            guard await hooks.isEmpty(space) == true else { return .protected }
            let remaining = await spaces(on: display)
            guard remaining.filter({ !$0.isFullscreen }).count > 1,
                  remaining.count == place.count, remaining.indices.contains(place.index),
                  remaining[place.index].id == space, !remaining[place.index].isFullscreen else { return .protected }
        }
        guard await hooks.perform(Self.removeAction, place.index, place.count, display) else {
            // Nothing was sent. The desktop may be gone already: an earlier request can land just
            // after the wait for it ran out.
            return await isGone(space, on: display) ? .gone : .unreadable
        }
        return await wait(until: { await self.isGone(space, on: display) }) ? .gone : .ignored
    }

    /// Removes a desktop this class added, in a Mission Control session of its own, unless a
    /// window has been put on it meanwhile.
    private func discard(_ temporary: SpaceInfo, on display: DisplayID, in run: Run) async {
        var removed = false
        if hooks.windowCount(temporary.id) == 0, await open(run) {
            removed = await delete(temporary.id, on: display) == .gone
            await close(run)
        }
        if !removed { hooks.report(Self.leftBehind) }
    }

    /// Where a desktop's button is and how many buttons the bar has, once the bar is at rest and
    /// the button names that desktop.
    private func position(of space: SpaceID, on display: DisplayID, offering action: String?) async -> (index: Int, count: Int)? {
        guard let bar = await settledBar(on: display, offering: action),
              let index = bar.spaces.firstIndex(where: { $0.id == space }),
              Self.names(buttonAt: index, of: bar.buttons, for: bar.spaces) else { return nil }
        return (index, bar.buttons.count)
    }

    /// The bar once there is one button per Space and the buttons have stopped moving; with
    /// `action`, also once every ordinary desktop's button offers it (whether a full-screen
    /// Space's button ever offers `AXRemoveDesktop` was not measured). A collapsed bar reports its
    /// labels above the screen even at rest, so position is no test; equal reads are (design
    /// appendix A). Stopped means two re-reads in a row that agree with the read before them,
    /// three equal reads in all; a read that fails starts the count again.
    private func settledBar(on display: DisplayID, offering action: String?) async -> Bar? {
        var last: [CGRect]?
        var steady = 0
        var settled: Bar?
        _ = await wait {
            guard let buttons = await self.hooks.buttons(display) else {
                last = nil
                return false
            }
            let frames = buttons.map(\.frame)
            steady = frames == last ? steady + 1 : 0
            last = frames
            guard steady >= 2 else { return false }
            let list = await self.spaces(on: display)
            guard buttons.count == list.count else { return false }
            if let action, !zip(buttons, list).allSatisfy({ $1.isFullscreen || $0.actions.contains(action) }) { return false }
            settled = (buttons, list)
            return true
        }
        return settled
    }

    private func spaces(on display: DisplayID) async -> [SpaceInfo] {
        await hooks.spaces().filter { $0.displayID == display }
    }

    private func isCurrent(_ space: SpaceID) async -> Bool {
        await hooks.spaces().first { $0.id == space }?.isCurrent == true
    }

    /// Whether a desktop has left the Space list. An empty list could not be read, and says
    /// nothing.
    private func isGone(_ space: SpaceID, on display: DisplayID) async -> Bool {
        let list = await spaces(on: display)
        return !list.isEmpty && !list.contains { $0.id == space }
    }

    /// True once Mission Control is known to be showing. It is toggled only when it is known to
    /// be closed: a toggle sent without knowing could close what was open.
    private func open(_ run: Run) async -> Bool {
        guard let showing = await shows() else { return false }
        // From here on Mission Control shows or is told to: closing it is this operation's.
        run.mayBeShowing = true
        if showing { return true }
        await hooks.toggle()
        return await wait { await self.hooks.isOpen() == true }
    }

    /// Closes Mission Control when it is known to be showing, and does nothing at all for an
    /// operation that never opened it nor found it showing. No answer is not taken for "closed".
    /// The result is what there is to report if the operation ends here: Mission Control still
    /// shows, or the Dock does not say; nil when it is closed.
    @discardableResult
    private func close(_ run: Run) async -> String? {
        guard run.mayBeShowing else { return nil }
        var showing = await shows()
        if showing == true {
            await hooks.toggle()
            _ = await wait {
                showing = await self.hooks.isOpen()
                return showing == false
            }
        }
        switch showing {
        case .some(false): return nil
        case .some(true): return Self.stillShowing
        case .none: return Self.stateUnknown
        }
    }

    /// Whether Mission Control is showing, asked until the Dock says; nil when it never did.
    private func shows() async -> Bool? {
        var answer: Bool?
        _ = await wait {
            answer = await self.hooks.isOpen()
            return answer != nil
        }
        return answer
    }

    /// Checks until `done` answers true; false when the checks run out. Cancelling the task does
    /// not cut it short.
    private func wait(until done: () async -> Bool) async -> Bool {
        for _ in 0..<pollLimit {
            if await done() { return true }
            await hooks.pause()
        }
        return await done()
    }
}
