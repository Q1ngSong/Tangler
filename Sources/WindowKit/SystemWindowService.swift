import AppKit
import ApplicationServices
import Contracts
import CoreKit
import Foundation

/// The real `WindowService`: Accessibility for windows, the window server for identity and
/// stacking order, and SkyLight, when this Mac offers it, for Spaces (design section 3.3).
/// Observation starts on first use; the App may call `start()` earlier and `stop()` on quit.
public final class SystemWindowService: WindowService, @unchecked Sendable {
    public let capabilities: WindowCapabilities
    /// Each private ability, whether it is available and why not, for the diagnostics page.
    public let capabilityStatuses: [WindowCapabilityStatus]

    let ownPID = ProcessInfo.processInfo.processIdentifier
    let stamps: ReadStamps
    let broadcaster: Broadcaster<WindowEvent>
    let registry: WindowRegistry<AXHandle>
    let source: AXInventorySource
    let privateSpaces: PrivateSpaces?
    let actions: WindowActions
    let displayCache = Locked<[DisplayInfo]>([])
    /// The desktops last seen, for `.spacesChanged`.
    let desktopWatch = DesktopWatch()

    let eventQueue = DispatchQueue(label: "app.local.tangler.window-events", qos: .userInitiated)
    let scanQueue = DispatchQueue(label: "app.local.tangler.window-inventory", qos: .userInitiated)
    let actionQueue = DispatchQueue(label: "app.local.tangler.window-actions", qos: .userInitiated)
    /// Reads and presses of applications' menus. A busy application holds a read for seconds,
    /// which must not hold up the window actions.
    let menuQueue = DispatchQueue(label: "app.local.tangler.app-menus", qos: .userInitiated)
    /// Reads of the Dock's whole area, which wait on the Dock's process.
    let dockFrameQueue = DispatchQueue(label: "app.local.tangler.dock-frame", qos: .userInitiated)
    /// Reads and actions on Mission Control, which wait on the Dock's process.
    let missionControlQueue = DispatchQueue(label: "app.local.tangler.mission-control", qos: .userInitiated)
    /// Dock hit tests, which wait on the Dock's process.
    let dockLookup = LatestLookup<(point: CGPoint, displays: [DisplayInfo]), DockItem?>(
        queue: DispatchQueue(label: "app.local.tangler.dock-reads", qos: .userInitiated)
    ) { DockReader.item(at: $0.point, displays: $0.displays) }

    private let lifecycle = Lifecycle()
    private let workspace = WorkspaceMonitor()
    let frames: FramePipeline<AXFrameBackend>
    // Assigned once at the end of init; they capture `self` weakly.
    private(set) var scans: ScanCoordinator!
    private(set) var handler: WindowEventHandler<AXInventorySource>!
    private(set) var hub: ObserverHub<AXObserverBackend>!
    private var notifications: NotificationDispatch<AXHandle>!
    private(set) var spaceMoves: SpaceMoves!
    private(set) var missionControl: MissionControl!
    private(set) var desktopSwiper: DesktopSwiper!
    private(set) var desktopSwitcher: DesktopSwitcher!
    private(set) var newWindows: NewWindowOpener!
    private let desktopReports = DesktopReports()
    /// One desktop operation at a time, Mission Control's or a swipe.
    private let desktopGate = DesktopGate()
    private var expose: ExposeWatcher!
    private var permission: PermissionMonitor!

    /// Probes the private abilities (design section 5.2); makes no request of other apps.
    public convenience init() {
        self.init(statuses: CapabilityProbe.probe(LiveProbe.environment()))
    }

    /// With the abilities as given, for tests of what a Mac without some of them answers.
    init(statuses: [WindowCapabilityStatus]) {
        let capabilities = CapabilityProbe.capabilities(of: statuses)
        let stamps = ReadStamps()
        let broadcaster = Broadcaster<WindowEvent>()
        let identity = capabilities.contains(.exactWindowIDs) ? WindowIdentity() : nil
        let spaces = capabilities.contains(.spaceList) ? PrivateSpaces() : nil
        let finder = capabilities.contains(.otherSpaceWindows) ? identity.flatMap { RemoteWindowFinder(identity: $0) } : nil
        capabilityStatuses = statuses
        self.capabilities = capabilities
        self.stamps = stamps
        self.broadcaster = broadcaster
        privateSpaces = spaces
        actions = WindowActions(preciseFocus: capabilities.contains(.preciseFocus) ? PreciseFocus() : nil)
        source = AXInventorySource(stamps: stamps, identity: identity, spaces: spaces, remoteFinder: finder)
        registry = WindowRegistry { broadcaster.send($0) }
        frames = FramePipeline(backend: AXFrameBackend(stamps: stamps))
        wire()
    }

    deinit {
        stop()
    }

    /// Starts observing windows. Safe to call more than once.
    public func start() {
        lifecycle.start {
            AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), AXRead.timeout)
            hub.start()
            workspace.start(queue: eventQueue) { [weak self] in self?.handle($0) }
            let trusted = AXIsProcessTrusted()
            permission.start(initial: trusted) { [weak self] granted in self?.authorizationChanged(granted) }
            expose.start()
            if trusted { activate() }
        }
    }

    /// Stops observing, ends running animations and gives apps back their
    /// `AXEnhancedUserInterface` flag.
    public func stop() {
        lifecycle.stop {
            permission.stop()
            workspace.stop()
            // Before the hub: letting the Dock's observer go takes the hub's thread.
            expose.stop()
            hub.stop()
            frames.stop()
        }
    }

    public var isAuthorized: Bool { AXIsProcessTrusted() }

    public var isExposeShowing: Bool { expose.isShowing }

    /// Shows the system prompt leading to the Accessibility settings and returns whether
    /// permission is already granted. Only the App's permission guide should call this.
    @discardableResult
    public func requestAccessibilityPermission() -> Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    public func events() -> AsyncStream<WindowEvent> {
        start()
        return broadcaster.stream()
    }

    /// Sets who is told what a desktop operation could not put right and no result carries, such
    /// as a temporary desktop left behind; nil tells nobody. The diagnostic log gets it either
    /// way. The handler is called on whatever thread the operation runs on.
    public func onDesktopReport(_ handler: (@Sendable (String) -> Void)?) {
        desktopReports.handler.value = handler
    }

    // MARK: Wiring

    private func wire() {
        let source = self.source
        let ownPID = self.ownPID
        scans = ScanCoordinator(queue: scanQueue) { [weak self] scope in self?.performScan(scope) }
        notifications = NotificationDispatch(enqueue: { [eventQueue] in eventQueue.async(execute: $0) }) {
            [weak self] notification, element, pid in self?.handler.handle(notification, element: element, pid: pid)
        }
        let backend = AXObserverBackend { [weak self] pid, name, element in
            self?.deliver(pid: pid, name: name, element: element)
        }
        hub = ObserverHub(backend: backend)
        expose = makeExposeWatcher(backend: backend)
        handler = WindowEventHandler(source: source, registry: registry, hooks: WindowEventHandler.Hooks(
            application: { Self.application($0, ownPID: ownPID) },
            frontmostPID: { NSWorkspace.shared.frontmostApplication?.processIdentifier },
            ownPID: ownPID,
            focusedWindow: { source.focusedWindow(of: $0) },
            record: { source.record(of: $0) },
            displays: { [displayCache] in displayCache.value },
            noticesDesktopChange: { [weak self] in self?.readsDesktopChange() ?? false },
            emit: { [broadcaster] in broadcaster.send($0) },
            scheduleScan: { [weak self] scope in self?.scans.schedule(scope, after: 0.15) },
            scheduleFollowUpScan: { [weak self, eventQueue] scope in
                eventQueue.asyncAfter(deadline: .now() + 1.5) { self?.scans.schedule(scope, after: 0) }
            },
            observe: { [weak self] handle, pid in self?.hub.observe(handle, pid: pid) },
            forget: { [weak self] handle, pid in self?.hub.forget(handle, pid: pid) }))
        spaceMoves = makeSpaceMoves()
        missionControl = makeMissionControl()
        desktopSwiper = makeDesktopSwiper()
        desktopSwitcher = makeDesktopSwitcher()
        newWindows = makeNewWindowOpener()
        permission = PermissionMonitor(queue: eventQueue) { AXIsProcessTrusted() }
    }

    private func makeSpaceMoves() -> SpaceMoves {
        let status = capabilityStatuses.first { $0.capability == .moveAcrossSpaces }
        let available = capabilities.contains(.moveAcrossSpaces)
        let spaces = privateSpaces
        let source = self.source
        return SpaceMoves(unavailableReason: available ? nil : status?.reason ?? "",
                          hooks: SpaceMoves.Hooks(
            spaces: { [weak self] in await self?.spaces() ?? [] },
            membership: { spaces?.spaceIDs(of: $0) },
            record: { source.record(of: $0) },
            start: { SpaceMover.start(moving: $0, to: $1) },
            pause: { await Self.movePause() },
            confirmed: { [weak self] id, spaceIDs in
                guard let self else { return }
                self.registry.update(id, fields: .spaces, stamp: self.stamps.next()) { $0.spaceIDs = spaceIDs }
            }))
    }

    private func makeMissionControl() -> MissionControl {
        let status = capabilityStatuses.first { $0.capability == .manageSpaces }
        let available = capabilities.contains(.manageSpaces)
        let spaces = privateSpaces
        let source = self.source
        let dock = missionControlQueue
        let reports = desktopReports
        return MissionControl(unavailableReason: available ? nil : status?.reason ?? L10n.text("windowkit.unavailable.on.this.mac"),
                              gate: desktopGate, hooks: MissionControl.Hooks(
            isAuthorized: { AXIsProcessTrusted() },
            isScreenLocked: { ScreenLock.isLocked() },
            spaces: { [weak self] in await self?.spaces() ?? [] },
            isOpen: { await Self.blocking(on: dock) { MissionControlReader.isOpen() } },
            toggle: { DockNotification.toggleMissionControl() },
            buttons: { display in await Self.blocking(on: dock) { MissionControlReader.buttons(on: display) } },
            pressAdd: { display in await Self.blocking(on: dock) { MissionControlReader.pressAdd(on: display) } },
            perform: { action, position, count, display in
                await Self.blocking(on: dock) {
                    MissionControlReader.perform(action, onButton: position, of: count, on: display)
                }
            },
            windowCount: { space in
                guard let spaces, let records = source.windowServerRecords() else { return nil }
                return SpaceOccupancy.count(on: space, records: records) { spaces.spaceIDs(of: $0) }
            },
            pause: { await Self.pause(milliseconds: 40) },
            report: { reports.send($0) },
            isEmpty: { [weak self] space in await self?.isSpaceEmpty(space) }))
    }

    private func makeDesktopSwiper() -> DesktopSwiper {
        let dock = missionControlQueue
        return DesktopSwiper(gate: desktopGate, hooks: DesktopSwiper.Hooks(
            isAuthorized: { AXIsProcessTrusted() },
            isScreenLocked: { ScreenLock.isLocked() },
            isMissionControlOpen: { await Self.blocking(on: dock) { MissionControlReader.isOpen() } },
            spaces: { [weak self] in await self?.spaces() ?? [] },
            pointerDisplay: { [weak self] in
                guard let self, let pointer = CGEvent(source: nil)?.location else { return nil }
                return DisplayLocator.display(at: pointer, in: await self.currentDisplays())?.id
            },
            naturalScrolling: { DockSwipe.naturalScrolling() },
            post: { DockSwipe.post(sign: $0) },
            pause: { await Self.pause(milliseconds: 10) }))
    }

    private func makeExposeWatcher(backend: AXObserverBackend) -> ExposeWatcher {
        let observer = ExposeObserver(backend: backend)
        let events = eventQueue
        let dock = missionControlQueue
        return ExposeWatcher(hooks: ExposeWatcher.Hooks(
            isAuthorized: { AXIsProcessTrusted() },
            dockPID: { DockReader.pid() },
            observe: { observer.attach(pid: $0) },
            stopObserving: { observer.detach() },
            isMissionControlOpen: { answer in dock.async { answer(MissionControlReader.isOpen()) } },
            after: { seconds, work in events.asyncAfter(deadline: .now() + seconds, execute: work) },
            emit: { [broadcaster] in broadcaster.send(.exposeChanged(isShowing: $0)) }))
    }

    private func makeDesktopSwitcher() -> DesktopSwitcher {
        DesktopSwitcher(hooks: DesktopSwitcher.Hooks(
            spaces: { [weak self] in await self?.spaces() ?? [] },
            swipe: { [weak self] space in await self?.desktopSwiper.swipe(to: space) == .arrived },
            windows: { [weak self] in await self?.windows() ?? [] },
            focusedWindow: { [weak self] in await self?.focusedWindowID() },
            focus: { [weak self] id in await self?.focus(id) ?? .failure(.windowNotFound(id)) },
            show: { [weak self] space in await self?.missionControl.show(space) ?? .failure(.rejected(L10n.text("windowkit.could.not.switch.to.the.target.desktop"))) },
            pause: { await Self.pause(milliseconds: 50) }))
    }

    private func makeNewWindowOpener() -> NewWindowOpener {
        let spaces = privateSpaces
        let source = self.source
        let queue = menuQueue
        return NewWindowOpener(hooks: NewWindowOpener.Hooks(
            items: { pid in await Self.blocking(on: queue) { AppMenuReader.items(of: pid) } },
            press: { item, pid in await Self.blocking(on: queue) { AppMenuReader.press(item, of: pid) } },
            windows: { pid in
                // A hidden application's windows are on no Space; they count as open (see
                // `UnlistedWindows`), so that unhiding it does not make them all look new. The
                // application is left hidden.
                let hidden = NSRunningApplication(processIdentifier: pid)?.isHidden ?? false
                return Set((source.windowServerRecords() ?? []).filter {
                    $0.pid == pid && SpaceOccupancy.isOpen($0, appIsHidden: hidden, spaceIDs: spaces?.spaceIDs(of: $0.id))
                }.map(\.id))
            },
            pause: { await Self.pause(milliseconds: 40) },
            // `entry(for:)` reads the application again while it does not know the window.
            isKnown: { [weak self] id in await self?.entry(for: id) != nil },
            settle: { await Self.pause(milliseconds: 100) }))
    }

    // MARK: Observation

    private func activate() {
        eventQueue.async { [weak self] in
            guard let self else { return }
            for app in Self.manageableApplications(excluding: self.ownPID) { self.hub.attach(pid: app.pid) }
            self.expose.sync()
            self.scans.schedule(.all, after: 0)
        }
    }

    private func authorizationChanged(_ granted: Bool) {
        if granted { activate() } else { hub.detachAll() }
        expose.sync()
    }

    /// Called on the observer thread; the work happens on the event queue.
    private func deliver(pid: Int32, name: String, element: AXUIElement) {
        if let signal = ExposeSignal(name: name) {
            return eventQueue.async { [weak self] in self?.expose.handle(signal, from: pid) }
        }
        guard let notification = WindowNotification(name: name) else { return }
        notifications.deliver(notification, element: AXHandle(element: element), pid: pid)
    }

    /// Runs on the event queue.
    private func handle(_ change: WorkspaceChange) {
        switch change {
        case .launched(let pid):
            // The Dock may be the one that launched, again. It is no manageable application, and
            // any launch is a moment to look whether the Dock is another one by now.
            expose.sync()
            guard pid != ownPID else { return }
            if Self.application(pid, ownPID: ownPID) != nil { hub.attach(pid: pid) }
            handler.applicationLaunched(pid)
        case .terminated(let pid):
            expose.applicationTerminated(pid)
            hub.detach(pid: pid)
            source.forget(pid: pid)
            handler.applicationTerminated(pid)
        case .hidden(let pid): handler.applicationHidden(pid)
        case .unhidden(let pid): handler.applicationUnhidden(pid)
        case .activated(let pid): handler.applicationActivated(pid)
        case .activeSpaceChanged: handler.activeSpaceChanged()
        case .displaysChanged:
            Task { [weak self] in
                guard let self else { return }
                await self.refreshDisplays()
                self.eventQueue.async { self.handler.displaysChanged() }
            }
        case .woke: scans.schedule(.all, after: 0.5)
        }
    }

    /// Runs on the scan queue.
    private func performScan(_ scope: ScanScope) {
        guard AXIsProcessTrusted() else { return }
        let running = Self.manageableApplications(excluding: ownPID)
        let apps: [AppSnapshot]
        switch scope {
        case .all: apps = running
        case .applications(let pids): apps = running.filter { pids.contains($0.pid) }
        }
        let scanner = InventoryScanner(source: source, discoversOtherSpaces: capabilities.contains(.otherSpaceWindows),
                                       concurrent: true)
        let result = scanner.scan(apps: apps, isFull: scope == .all, known: registry.allEntries(),
                                  displays: displayCache.value)
        registry.apply(result)
        noteDesktops()
        // Keep notifications in step with the applications and windows just read.
        if let running = result.runningPIDs {
            for pid in hub.attachedPIDs.subtracting(running) { hub.detach(pid: pid) }
        }
        for pid in result.scannedPIDs {
            hub.attach(pid: pid)
            hub.sync(pid: pid, windows: registry.entries(pid: pid).map(\.handle))
        }
    }

    // MARK: Desktops

    /// Reads the Space list; true when its desktops are not the ones last seen. The displays keep
    /// the window server's own names here: the display list may not be loaded yet, and a name
    /// that changed once it is would pass for a change of desktops.
    private func readsDesktopChange() -> Bool {
        guard let raw = privateSpaces?.displaySpaces() else { return false }
        return desktopWatch.noticesChange(in: SpaceParser.spaces(from: raw, mainDisplayID: nil))
    }

    /// Announces a change of the desktops that happened behind the service's back: the user
    /// added or removed one in Mission Control, or an application went full screen. Called where
    /// the service looks at the system anyway, after every scan.
    func noteDesktops() {
        if readsDesktopChange() { broadcaster.send(.spacesChanged) }
    }

    /// After an operation that changed the desktops and took `desktopWatch.changes` before it
    /// began: makes sure the change is announced, once.
    func announceDesktops(changedSince mark: Int) {
        noteDesktops()
        if desktopWatch.claimsChange(since: mark) { broadcaster.send(.spacesChanged) }
    }

    // MARK: Helpers

    /// Starts observation on first use; with `prime`, also makes sure one full scan has run,
    /// so the registry answers for every window.
    func prepare(prime: Bool = true) async -> Bool {
        start()
        guard AXIsProcessTrusted() else { return false }
        if displayCache.value.isEmpty { await refreshDisplays() }
        if prime && !registry.isPrimed { await scans.scan(.all) }
        return true
    }

    @discardableResult
    func refreshDisplays() async -> [DisplayInfo] {
        let snapshots = await MainActor.run { ScreenReader.snapshots() }
        let displays = DisplayConversion.displays(from: snapshots)
        displayCache.value = displays
        return displays
    }

    func currentDisplays() async -> [DisplayInfo] {
        let cached = displayCache.value
        return cached.isEmpty ? await refreshDisplays() : cached
    }

    /// The registry's entry, scanning the window's application first if it is not known yet.
    func entry(for id: WindowID) async -> WindowRegistry<AXHandle>.Entry? {
        if let entry = registry.entry(id) { return entry }
        guard let pid = source.record(of: id)?.pid else { return nil }
        await scans.scan(.applications([pid]))
        return registry.entry(id)
    }

    func run<T>(on queue: DispatchQueue, _ work: @escaping () -> T) async -> T {
        await Self.blocking(on: queue, work)
    }

    /// Runs work that waits on another process, such as Accessibility calls into the Dock, on
    /// `queue` instead of a cooperative-pool thread. Static, so a hook need not hold the service.
    static func blocking<T>(on queue: DispatchQueue, _ work: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    /// Waits whether or not the task is cancelled: `Task.sleep` returns at once in a cancelled
    /// task, and an operation that has started has to run to its end.
    static func pause(milliseconds: Int) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .milliseconds(milliseconds)) {
                continuation.resume()
            }
        }
    }

    /// The wait between two checks of a window's move to another desktop. It never gives the
    /// wait up: the move is under way, also when the task was cancelled meanwhile.
    static func movePause() async -> Bool {
        await pause(milliseconds: 50)
        return true
    }

    static func application(_ pid: Int32, ownPID: Int32) -> AppSnapshot? {
        guard pid != ownPID, let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
              app.activationPolicy == .regular else { return nil }
        return snapshot(of: app)
    }

    static func manageableApplications(excluding ownPID: Int32) -> [AppSnapshot] {
        NSWorkspace.shared.runningApplications
            .filter { !$0.isTerminated && $0.activationPolicy == .regular && $0.processIdentifier != ownPID }
            .map(snapshot(of:))
    }

    private static func snapshot(of app: NSRunningApplication) -> AppSnapshot {
        AppSnapshot(pid: app.processIdentifier, bundleID: app.bundleIdentifier,
                    name: app.localizedName ?? app.bundleIdentifier ?? L10n.text("windowkit.application"), isHidden: app.isHidden)
    }
}
