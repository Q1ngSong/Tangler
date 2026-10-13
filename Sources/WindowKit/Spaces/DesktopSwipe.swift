import Contracts

/// The way to a Space with Dock swipes: which way, and the Spaces passed on the way.
enum DesktopSwipe {
    enum Direction: Equatable {
        case left, right
    }

    struct Route: Equatable {
        var direction: Direction
        /// The Space each swipe should land on, the target last.
        var stops: [SpaceID]
    }

    /// From the Space showing on `space`'s display to `space`, counted in that display's whole
    /// Space order: a full-screen Space between two desktops takes a swipe of its own. Nil when
    /// the Space is not listed, is the one showing, or its display shows none.
    static func route(to space: SpaceID, among spaces: [SpaceInfo]) -> Route? {
        guard let display = spaces.first(where: { $0.id == space })?.displayID else { return nil }
        let row = spaces.filter { $0.displayID == display }
        guard let from = row.firstIndex(where: \.isCurrent), let to = row.firstIndex(where: { $0.id == space }),
              from != to else { return nil }
        if from < to { return Route(direction: .right, stops: row[(from + 1)...to].map(\.id)) }
        return Route(direction: .left, stops: row[to..<from].reversed().map(\.id))
    }

    /// The sign the swipe event carries. With "natural scrolling" on, or never set, right is +1
    /// and left −1: measured on 26.6.1 with it on. With it off the two are swapped, which is
    /// jurplel/InstantSpaceSwitcher's rule and was not measured here; a wrong sign lands on the
    /// other side, the swiping stops and the slower route takes over.
    static func sign(_ direction: Direction, naturalScrolling: Bool?) -> Double {
        let natural: Double = direction == .right ? 1 : -1
        return naturalScrolling == false ? -natural : natural
    }
}

/// Lets one desktop operation run at a time: Mission Control's and the swipes share one.
final class DesktopGate: Sendable {
    private let busy = Locked(false)

    /// False when another operation holds the gate; after true, `leave` gives it back.
    func enter() -> Bool {
        busy.update { held -> Bool in
            if held { return false }
            held = true
            return true
        }
    }

    func leave() {
        busy.value = false
    }
}

/// Goes to an ordinary desktop on the same display with synthetic Dock swipes, one Space at a
/// time, which takes about 50 ms a step and shows no animation. A posted swipe proves nothing:
/// after each one the Space list has to show the expected neighbour, and a step that lands
/// elsewhere or nowhere ends the swiping, so that the caller goes on from wherever the screen
/// is. Never while the screen is locked, Mission Control shows or the Dock does not say, another
/// desktop operation runs, or without the Accessibility permission.
final class DesktopSwiper: @unchecked Sendable {
    struct Hooks {
        var isAuthorized: () -> Bool
        var isScreenLocked: () -> Bool
        /// Whether Mission Control is showing; nil when the Dock did not say.
        var isMissionControlOpen: () async -> Bool?
        /// Every Space in the window server's order, full-screen ones included.
        var spaces: () async -> [SpaceInfo]
        /// The display under the pointer, which is the one a swipe acts on. Asked only when the
        /// Space list names more than one display.
        var pointerDisplay: () async -> DisplayID?
        /// The "natural scrolling" preference; nil when it was never set.
        var naturalScrolling: () -> Bool?
        /// Posts one swipe with this sign.
        var post: (Double) -> Void
        /// Waits between checks, also in a cancelled task.
        var pause: () async -> Void
    }

    enum Outcome: Equatable {
        /// The Space list shows the target.
        case arrived
        /// Nothing was posted.
        case notTried
        /// A swipe was posted and did not land on the Space expected.
        case strayed
    }

    /// How many switches the swipes completed; the device test reads it.
    let arrivals = Locked(0)

    private let gate: DesktopGate
    private let pollLimit: Int
    private let hooks: Hooks

    /// The wait for one step gives up after `pollLimit` pauses: 300 ms with the live 10 ms pause.
    init(gate: DesktopGate = DesktopGate(), pollLimit: Int = 30, hooks: Hooks) {
        self.gate = gate
        self.pollLimit = pollLimit
        self.hooks = hooks
    }

    func swipe(to space: SpaceID) async -> Outcome {
        guard hooks.isAuthorized(), !hooks.isScreenLocked(), gate.enter() else { return .notTried }
        defer { gate.leave() }
        let all = await hooks.spaces()
        guard let target = all.first(where: { $0.id == space }), !target.isFullscreen,
              let route = DesktopSwipe.route(to: space, among: all) else { return .notTried }
        // With Spaces of their own, the display under the pointer is the one that swipes.
        if Set(all.map(\.displayID)).count > 1 {
            guard await hooks.pointerDisplay() == target.displayID else { return .notTried }
        }
        guard await hooks.isMissionControlOpen() == false else { return .notTried }
        let sign = DesktopSwipe.sign(route.direction, naturalScrolling: hooks.naturalScrolling())
        var here = all.first { $0.displayID == target.displayID && $0.isCurrent }?.id
        for stop in route.stops {
            hooks.post(sign)
            let landed = await current(on: target.displayID, after: here)
            guard landed == stop else { return .strayed }
            here = landed
        }
        arrivals.update { $0 += 1 }
        return .arrived
    }

    /// The Space showing on `display` once it is no longer `before`; `before` when the wait ran out.
    private func current(on display: DisplayID, after before: SpaceID?) async -> SpaceID? {
        for _ in 0..<pollLimit {
            if let now = await showing(on: display), now != before { return now }
            await hooks.pause()
        }
        return await showing(on: display) ?? before
    }

    private func showing(on display: DisplayID) async -> SpaceID? {
        await hooks.spaces().first { $0.displayID == display && $0.isCurrent }?.id
    }
}
