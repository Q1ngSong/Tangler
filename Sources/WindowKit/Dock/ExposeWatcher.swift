import Foundation

/// Which of the Dock's three ways of laying the windows out is up.
enum ExposeKind: Equatable {
    case missionControl
    case appExpose
    case showDesktop
}

/// What the Dock posts on its application element about Exposé (measured on macOS 26.6.1 with
/// LiveExposeSignalProbe): one of three names 265 to 277 ms after Mission Control, App Exposé or
/// Show Desktop was asked for, and one name about 255 ms after it was dismissed.
enum ExposeSignal: Equatable {
    case began(ExposeKind)
    case ended

    /// The accessibility notifications to register on the Dock.
    static let names = ["AXExposeShowAllWindows", "AXExposeShowFrontWindows", "AXExposeShowDesktop", "AXExposeExit"]

    init?(name: String) {
        switch name {
        case "AXExposeShowAllWindows": self = .began(.missionControl)
        case "AXExposeShowFrontWindows": self = .began(.appExpose)
        case "AXExposeShowDesktop": self = .began(.showDesktop)
        case "AXExposeExit": self = .ended
        default: return nil
        }
    }
}

/// Knows whether Mission Control, App Exposé or Show Desktop is showing, from the Dock's
/// notifications, and says so whenever that changes. It observes the Dock that runs now: the Dock
/// quitting ends whatever was showing, and the next `sync` observes the one that runs then. Without
/// Accessibility permission, and while not started, nothing is observed and nothing shows.
///
/// What ends "showing":
/// - the Dock's exit notification, for all three;
/// - the Dock quitting, permission taken away, `stop`;
/// - for Mission Control alone, a missed exit: while it shows, the Dock is asked once a second
///   whether it is open (`MissionControlReader.isOpen()`), and two answers "closed" in a row end
///   it. Two, because the first "closed" comes about a quarter of a second before the exit
///   notification, while the windows still fly back.
///
/// The hole: App Exposé and Show Desktop have nothing to ask (`isOpen()` says false throughout),
/// so a missed exit leaves them "showing" until the next Exposé of any kind ends, or the Dock
/// quits. Nothing else is taken for their end. Another application coming to the front or a window
/// taking the focus is no evidence: clicking the desktop during Show Desktop does both and the
/// windows stay away, and so does ⌘Tab during App Exposé. No missed exit has been seen.
///
/// The other way round, an Exposé that was up before the Dock was observed is not known, except
/// Mission Control, which is asked about once when the observation begins.
///
/// Every call is serialized here; the hooks' answers may come on any thread, also at once.
final class ExposeWatcher: @unchecked Sendable {
    struct Hooks {
        var isAuthorized: () -> Bool
        /// The Dock's process; nil while it is not running.
        var dockPID: () -> Int32?
        /// Registers `ExposeSignal.names` on that Dock; whatever was observed before is let go.
        var observe: (Int32) -> RegistrationResult
        var stopObserving: () -> Void
        /// Asks the Dock whether Mission Control is open and answers later; nil when it cannot be told.
        var isMissionControlOpen: (@escaping (Bool?) -> Void) -> Void
        /// Runs the work after so many seconds.
        var after: (TimeInterval, @escaping () -> Void) -> Void
        /// "Showing" changed.
        var emit: (Bool) -> Void
    }

    /// The pause between two questions about Mission Control, and before another try to observe
    /// a Dock that did not answer, as one that is still launching does not.
    static let watchInterval: TimeInterval = 1
    static let retryDelay: TimeInterval = 1
    static let maxAttempts = 5
    /// How many answers "closed" in a row end Mission Control without an exit notification.
    static let closedReadsToEnd = 2

    private let hooks: Hooks
    // Recursive: a hook may answer before it returns.
    private let lock = NSRecursiveLock()
    /// Read from any thread, also while a registration waits on the Dock.
    private let showing = Locked(false)
    private var isStarted = false
    private var kind: ExposeKind?
    private var observedPID: Int32?
    /// Bumped whenever `kind` changes; answers asked for before that are dropped.
    private var generation = 0
    private var attempts = 0

    init(hooks: Hooks) {
        self.hooks = hooks
    }

    var isShowing: Bool { showing.value }

    /// Observation itself begins with the next `sync`.
    func start() {
        locked { isStarted = true }
    }

    func stop() {
        locked {
            isStarted = false
            detach()
        }
    }

    /// Observes the Dock that runs now, unless it is observed already. For whenever that may have
    /// changed: permission granted or taken away, an application launched.
    func sync() {
        locked {
            guard isStarted, hooks.isAuthorized(), let pid = hooks.dockPID() else { return detach() }
            guard pid != observedPID else { return }
            detach()
            switch hooks.observe(pid) {
            case .registered:
                observedPID = pid
                attempts = 0
                let mark = generation
                hooks.isMissionControlOpen { [weak self] open in
                    self?.locked {
                        guard let self, open == true, self.generation == mark, self.observedPID == pid else { return }
                        self.set(.missionControl)
                    }
                }
            case .retryLater:
                attempts += 1
                guard attempts < Self.maxAttempts else { return }
                hooks.after(Self.retryDelay) { [weak self] in self?.sync() }
            case .abandoned:
                break
            }
        }
    }

    /// The Dock that quit takes what it showed with it.
    func applicationTerminated(_ pid: Int32) {
        locked {
            guard pid == observedPID else { return }
            detach()
        }
    }

    /// A notification of the Dock `pid`. One from a Dock no longer observed says nothing.
    func handle(_ signal: ExposeSignal, from pid: Int32) {
        locked {
            guard pid == observedPID else { return }
            switch signal {
            case .began(let kind): set(kind)
            case .ended: set(nil)
            }
        }
    }

    private func detach() {
        if observedPID != nil {
            hooks.stopObserving()
            observedPID = nil
        }
        set(nil)
    }

    private func set(_ kind: ExposeKind?) {
        guard kind != self.kind else { return }
        self.kind = kind
        generation += 1
        if kind == .missionControl { watchMissionControl(generation, closedReads: 0) }
        let isShowing = kind != nil
        let changed = showing.update { value -> Bool in
            defer { value = isShowing }
            return value != isShowing
        }
        if changed { hooks.emit(isShowing) }
    }

    /// The safety net for a missed exit, for as long as Mission Control is what shows.
    private func watchMissionControl(_ mark: Int, closedReads: Int) {
        hooks.after(Self.watchInterval) { [weak self] in
            guard let self, self.locked({ self.generation == mark }) else { return }
            self.hooks.isMissionControlOpen { [weak self] open in
                self?.locked {
                    guard let self, self.generation == mark else { return }
                    // An answer that is not "closed" starts the count again.
                    let closed = open == false ? closedReads + 1 : 0
                    if closed >= Self.closedReadsToEnd {
                        self.set(nil)
                    } else {
                        self.watchMissionControl(mark, closedReads: closed)
                    }
                }
            }
        }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
