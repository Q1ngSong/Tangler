import AppKit
import Contracts
import CoreGraphics
import CoreKit
import Foundation

/// Runs the Dock preview (design section 4.4): follows the pointer over the Dock, opens and
/// closes the preview, carries out its cards' buttons and the Dock click behaviour.
@MainActor
final class DockPreviewController {
    let windows: any WindowService
    let input: any InputService
    let capture: any CaptureService
    let scheduler: any DockScheduler
    let presenter: any DockPreviewPresenting
    /// The app in front according to AppKit. WindowKit's focused window outlasts Tangler's own
    /// windows coming to the front, so it cannot tell which app a Dock click starts from.
    let frontmostPID: @MainActor () -> Int32?
    /// Whether the Dock hides until the pointer reaches its edge; its hover is never hidden then.
    let dockAutohides: () -> Bool

    /// How long after an app launches or quits the Dock takes to settle into its new size.
    static let dockSettleDelay: TimeInterval = 1

    private(set) var settings = DockPreviewSettings.defaultValue
    /// The input the controller listens to; empty while the settings leave nothing to do.
    private(set) var subscription: InputEventFilter = []
    var machine: DockHoverMachine
    var displays: [DisplayInfo] = []
    /// The app being loaded while the pointer rests on its icon.
    var pending: DockPreviewSession?
    /// The app whose preview is open or opening.
    var shown: DockPreviewSession?
    var press: (gesture: DockClickGesture, target: Task<DockClickTarget?, Never>)?
    var clickWork: DockScheduledWork?

    /// Bumped when the preview state is reset, so answers to earlier lookups are dropped.
    private var generation = 0
    private var inputTask: Task<Void, Never>?
    private var windowTask: Task<Void, Never>?
    private var wakeUp: DockScheduledWork?
    private var wakeUpDeadline: TimeInterval?
    private var running: [UUID: Task<Void, Never>] = [:]
    private var shieldRefresh: DockScheduledWork?
    private var wasNearDock = false

    init(windows: any WindowService, input: any InputService, capture: any CaptureService,
         scheduler: any DockScheduler, presenter: any DockPreviewPresenting,
         frontmostPID: @escaping @MainActor () -> Int32? = { NSWorkspace.shared.frontmostApplication?.processIdentifier },
         dockAutohides: @escaping () -> Bool = DockPreferences.autohides) {
        self.windows = windows
        self.input = input
        self.capture = capture
        self.scheduler = scheduler
        self.presenter = presenter
        self.frontmostPID = frontmostPID
        self.dockAutohides = dockAutohides
        machine = DockHoverMachine(showDelay: settings.effectiveShowDelay, dismissDelay: settings.effectiveDismissDelay)
    }

    /// Takes new settings and listens only to the input they need: pointer moves only while
    /// previews are on, since they are frequent.
    func apply(_ settings: DockPreviewSettings) {
        self.settings = settings
        presenter.animates = settings.animates
        machine.showDelay = settings.effectiveShowDelay
        machine.dismissDelay = settings.effectiveDismissDelay
        if !settings.previewsEnabled { resetPreview() }
        if settings.clickBehavior == .systemDefault { cancelClick() }
        var filter: InputEventFilter = []
        if settings.previewsEnabled { filter.formUnion([.mouseMoved, .mouseButtons]) }
        if settings.clickBehavior != .systemDefault { filter.insert(.mouseButtons) }
        subscribe(filter)
        scheduleWakeUp()
        updateShield()
    }

    func stop() {
        subscribe([])
        resetPreview()
        cancelClick()
        shieldRefresh?.cancel()
        shieldRefresh = nil
        for task in running.values { task.cancel() }
        input.setMouseMoveShield(nil)
    }

    /// Waits until every request the controller started has finished; tests call it after each step.
    func settle() async {
        while let task = running.values.first { await task.value }
    }

    func handle(_ event: InputEvent) {
        switch event {
        case .mouseMoved(let point):
            guard settings.previewsEnabled else { return }
            let nearDock = mayBeOverDock(point)
            // The Dock may have changed size or place since: read it again before the pointer arrives.
            if nearDock && !wasNearDock && shieldsDock { updateShield() }
            wasNearDock = nearDock
            step(machine.pointerMoved(to: point, nearDock: nearDock, at: scheduler.now))
        case .mouseDown(let mouse):
            if settings.previewsEnabled { step(machine.mouseDown(at: mouse.location)) }
            beginPress(mouse)
        case .mouseDragged(let mouse):
            press?.gesture.dragged(to: mouse.location)
        case .mouseUp(let mouse):
            endPress(mouse)
        case .leaderTriggered, .shortcut, .modifiersChanged, .scroll:
            break
        }
    }

    func mayBeOverDock(_ point: CGPoint) -> Bool {
        DockPreviewGeometry.mayBeOverDock(point, displays: displays)
    }

    /// Whether pointer moves over the Dock are kept from it, hiding its own name labels.
    var shieldsDock: Bool {
        settings.previewsEnabled && settings.hidesDockHover && !dockAutohides()
    }

    /// Puts the shield over where the Dock is now, or lifts it.
    func updateShield() {
        guard shieldsDock else { return input.setMouseMoveShield(nil) }
        let windows = self.windows
        let input = self.input
        track { [weak self] in
            let dock = await windows.dockFrame()
            let displays = await windows.displays()
            guard let self, !Task.isCancelled, self.shieldsDock else { return }
            input.setMouseMoveShield(dock.map { DockShield.region(dock: $0, displays: displays) })
        }
    }

    /// An app came or went, and the Dock grows or shrinks for it: read it once it has settled.
    func refreshShieldSoon() {
        guard shieldsDock else { return }
        shieldRefresh?.cancel()
        shieldRefresh = scheduler.schedule(at: scheduler.now + Self.dockSettleDelay) { [weak self] in
            self?.shieldRefresh = nil
            self?.updateShield()
        }
    }

    /// Carries out the machine's effects, then keeps one wake-up for its next deadline.
    func step(_ effects: [DockHoverMachine.Effect]) {
        for effect in effects {
            switch effect {
            case .lookUp(let point): lookUp(point)
            case .prepare(let item): prepare(item)
            case .show(let item): show(item)
            case .hide: hidePanel()
            }
        }
        dropAbandonedSession()
        scheduleWakeUp()
    }

    func scheduleWakeUp() {
        let deadline = machine.nextDeadline
        guard deadline != wakeUpDeadline else { return }
        wakeUp?.cancel()
        wakeUp = nil
        wakeUpDeadline = deadline
        guard let deadline else { return }
        wakeUp = scheduler.schedule(at: deadline) { [weak self] in
            guard let self else { return }
            wakeUp = nil
            wakeUpDeadline = nil
            step(machine.advance(to: scheduler.now))
        }
    }

    /// Runs `work` as a task that `stop()` cancels and `settle()` waits for.
    @discardableResult
    func track(_ work: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let id = UUID()
        let task = Task { @MainActor [weak self] in
            await work()
            self?.running[id] = nil
        }
        running[id] = task
        return task
    }

    func reloadDisplays() {
        let windows = self.windows
        track { [weak self] in
            let displays = await windows.displays()
            guard let self else { return }
            self.displays = displays
            if !displays.isEmpty, let shown { present(shown) }
        }
    }

    private func lookUp(_ point: CGPoint) {
        let windows = self.windows
        let generation = self.generation
        track { [weak self] in
            let started = ContinuousClock.now
            let item = await windows.dockItem(at: point)
            let ms = started.duration(to: .now).components
            DiagnosticLog("dock").trace("Dock 查找：\(item.map { "「\($0.appName)」" } ?? "不在图标上")，用时 \(Int(Double(ms.seconds) * 1000 + Double(ms.attoseconds) / 1e15))ms")
            guard let self, generation == self.generation else { return }
            step(machine.lookupFinished(item, at: scheduler.now))
        }
    }

    private func subscribe(_ filter: InputEventFilter) {
        guard filter != subscription else { return }
        subscription = filter
        inputTask?.cancel()
        inputTask = nil
        guard !filter.isEmpty else {
            windowTask?.cancel()
            windowTask = nil
            return
        }
        let events = input.events(filter)
        inputTask = Task { [weak self] in
            for await event in events { self?.handle(event) }
        }
        guard windowTask == nil else { return }
        let changes = windows.events()
        windowTask = Task { [weak self] in
            for await change in changes { self?.handle(change) }
        }
        reloadDisplays()
    }

    private func resetPreview() {
        generation += 1
        wakeUp?.cancel()
        wakeUp = nil
        wakeUpDeadline = nil
        pending?.cancel()
        pending = nil
        hidePanel()
        machine = DockHoverMachine(showDelay: settings.effectiveShowDelay, dismissDelay: settings.effectiveDismissDelay)
    }
}
