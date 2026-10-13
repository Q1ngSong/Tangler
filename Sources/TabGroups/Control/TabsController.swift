import AppKit
import Contracts
import CoreGraphics
import CoreKit

/// Runs tab groups (tab groups design 4): keeps the groups, follows their windows, and carries out
/// commands and the bars' controls. Window events, input, settles, bar actions, commands and what
/// other modules ask go through one queue, each handled to the end before the next, so nothing
/// ever sees a group half changed. Tests leave it unstarted, hand it events with `process` and run
/// what it queued with `drain`.
@MainActor
final class TabsController {
    /// What a drag would add to a bar, or move within it.
    struct DropPreview: Equatable {
        var group: TabGroupID
        var tab: TabItem
        var slot: Int
    }

    /// A tab being dragged by its chip (tab drop preview design 4.3). Without ⌘ it only changes
    /// places in its own bar; with ⌘ alone it can also go to another bar or leave as a window.
    struct TabDrag: Equatable {
        var tab: WindowID
        var point: CGPoint
        var command: Bool
    }

    enum Event: Sendable {
        case window(WindowEvent)
        case input(InputEvent)
        /// A window came to rest after moving.
        case settled(WindowID)
        case reconcile
        case bar(TabBarAction)
        /// Settings and the layout they require take effect together, between window events.
        case settings
        /// The layout is about to ask a window to take a frame.
        case placing(PlacementRequest)
        case job(@MainActor @Sendable () async -> CommandResult, CheckedContinuation<CommandResult, Never>)
        /// Another module asks what the groups are, once everything queued before has been handled.
        case snapshots(CheckedContinuation<[TabGroupSnapshot], Never>)
    }

    static let reconcileDelay: TimeInterval = 0.1
    /// A dragged window or tab counts as over a bar this far above and below it.
    static let zoneSlack: CGFloat = 6
    /// The layout module snaps within this distance of a display's left and right edges, so bars
    /// take no drops there (tab groups design 4.2 item 4).
    static let edgeReach: CGFloat = 24
    /// A tab let go farther than this from its bar leaves the group.
    static let tearDistance: CGFloat = 24
    static var notGrouped: CommandResult { CommandResult.unavailable(reason: L10n.text("tabgroups.the.focused.window.is.not.in.a")) }
    static var stoppedReason: String { L10n.text("tabgroups.the.tab.group.module.has.stopped") }
    static var offDesktopReason: String { L10n.text("tabgroups.these.windows.are.not.on.the.current") }
    /// A window move this soon after a click, a drag or the leader key counts as the user's.
    static let gestureWindow: TimeInterval = 2
    /// A window placing itself this soon after it appeared is never a reason to merge.
    static let newWindowGrace: TimeInterval = 3

    let windows: any WindowService
    let input: any InputService
    /// Announces the frames the layout asks windows to take; nil while that module is off.
    let placement: (any PlacementService)?
    let presenter: any TabBarPresenting
    let scheduler: any TabScheduler
    let isAppHidden: (Int32) -> Bool
    let pick: @MainActor () async -> WindowInfo?
    let log = DiagnosticLog("tabs")

    var book = TabBook()
    private(set) var settings = TabGroupsSettings.defaultValue
    /// The newest known state of every grouped window, for the tabs' titles and icons.
    var infos: [WindowID: WindowInfo] = [:]
    var displays: [DisplayInfo] = []
    /// The Spaces on screen; empty when unknown, and then every group counts as on screen.
    var currentSpaces: Set<SpaceID> = []
    /// What Tangler last wrote to each window, and its writes under way: their echoes are not the user's.
    var written: [WindowID: CGRect] = [:]
    var writing: [WindowID: Int] = [:]
    /// Unacknowledged writes, including older slider values whose notifications are still queued.
    /// WindowKit reports the size and position separately; neither intermediate nor superseded
    /// frames may be interpreted as a new group area.
    var pendingWrites: [WindowID: [(from: CGRect?, to: CGRect)]] = [:]
    /// Height writes can report mixed frames even after their final readback was acknowledged.
    /// Validate the first unknown external frame against the window before following it.
    private var heightAdjustedWindows: Set<WindowID> = []
    /// A write Tangler undid in the same job, as when a window could not take a frame. Its report
    /// comes once the job is over, when it is no longer the last write, and is an echo all the same.
    var undone: [WindowID: CGRect] = [:]
    /// The size last written to each window and the size it took, where its application chose
    /// another: one that sizes its windows in steps, as Terminal does in character cells.
    var answers: [WindowID: (asked: CGSize, took: CGSize)] = [:]
    /// The frame the layout last asked each window to take, as it announced it, and whether it is a
    /// place to fill or the window's own frame. A window at what it made of that frame stands for
    /// the frame (`placement(of:at:)`). Forgotten once its group has come to rest there or Tangler
    /// writes the window itself, and when the window comes to rest somewhere else.
    var placements: [WindowID: (frame: CGRect, isZone: Bool)] = [:]
    /// The answers each window gave before its last, newest first, for a window the layout sends
    /// back where it was: at a size it took then, it stands for the size written then.
    var earlierAnswers: [WindowID: [(asked: CGSize, took: CGSize)]] = [:]
    static let answersKept = 8
    /// The latest live write to each inactive tab while its group moves.
    var syncs: [WindowID: Task<Void, Never>] = [:]
    /// Each group whose window in front is moving: that window, and the group's area as it was
    /// when the window last rested. Kept from the first report of a move until the group comes to
    /// rest, and good only while that window is the one in front (`resting`): a window that closed
    /// or gave way to another tab on the way never comes to rest there.
    var rested: [TabGroupID: (front: WindowID, area: CGRect)] = [:]
    /// Windows the user moved that have not come to rest yet.
    var userMoved: Set<WindowID> = []
    /// The last frame each window reported. WindowKit reports a move and a resize separately,
    /// with the same frame; the second report changes nothing.
    var lastSeen: [WindowID: CGRect] = [:]
    /// When the user last pressed a mouse button or the leader key.
    var lastGesture: TimeInterval?
    /// When each window appeared, while that is recent.
    var appearedAt: [WindowID: TimeInterval] = [:]
    /// The drop preview: at most one bar shows one.
    var dropPreview: DropPreview?
    /// The window being ⌘-dragged, as the tab it would become; read when its preview first shows.
    var draggedItem: TabItem?
    /// The bar brought to the front for the preview; it goes back above its window afterwards.
    var liftedBar: TabGroupID?
    /// The tab drag under way. The chip starts it; mouse events carry it on and end it, since a
    /// chip does not always hear the mouse come up.
    var tabDrag: TabDrag?
    /// When each group was last used; where bars overlap, the most recent one takes drops.
    var lastUsed: [TabGroupID: Int] = [:]
    var useCount = 0
    /// Windows that could not take a group's frame, and that frame: they are not tried again there.
    var refused: [WindowID: CGRect] = [:]
    var drag = JoinDragTracker()
    lazy var settle = SettleTracker(scheduler: scheduler, isLeftButtonDown: isLeftButtonDown) { [weak self] id in
        self?.submit(.settled(id))
    }
    lazy var onAction: @MainActor (TabBarAction) -> Void = { [weak self] action in self?.submit(.bar(action)) }

    let isLeftButtonDown: () -> Bool
    private var reconcileWork: TabScheduledWork?
    /// Bumped by every start and stop; events of a run that ended are dropped.
    private var run = 0
    private var queue: AsyncStream<Event>.Continuation?
    /// One pending settings event carries the latest slider value, never a backlog of old heights.
    private var pendingSettings: TabGroupsSettings?
    private var relayoutIncomplete = false
    /// Events submitted while not started, for tests to `drain`.
    private var backlog: [Event] = []
    private var forwarding: [Task<Void, Never>] = []
    private var inputTask: Task<Void, Never>?

    init(windows: any WindowService, input: any InputService, placement: (any PlacementService)? = nil,
         presenter: any TabBarPresenting, scheduler: any TabScheduler,
         isLeftButtonDown: @escaping () -> Bool = { NSEvent.pressedMouseButtons & 1 != 0 },
         isAppHidden: @escaping (Int32) -> Bool = { NSRunningApplication(processIdentifier: $0)?.isHidden ?? false },
         pick: @escaping @MainActor () async -> WindowInfo? = { nil }) {
        self.windows = windows
        self.input = input
        self.placement = placement
        self.presenter = presenter
        self.scheduler = scheduler
        self.isLeftButtonDown = isLeftButtonDown
        self.isAppHidden = isAppHidden
        self.pick = pick
    }

    var barHeight: CGFloat { settings.effectiveBarHeight }

    // MARK: Running

    func start() {
        stop()
        let run = self.run
        let (stream, queue) = AsyncStream.makeStream(of: Event.self)
        self.queue = queue
        presenter.ordersAboveWindow = windows.capabilities.contains(.exactWindowIDs)
        let events = windows.events()
        // After the subscription, so that no change between the two is lost.
        presenter.setHidden(windows.isExposeShowing)
        forwarding = [Task { [weak self] in for await event in events { self?.submit(.window(event)) } }]
        if let requests = placement?.requests() {
            forwarding.append(Task { [weak self] in for await request in requests { self?.submit(.placing(request)) } })
        }
        subscribeInput()
        Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                if self.run == run { await self.process(event) } else { Self.drop(event) }
            }
        }
        submit(.window(.displaysChanged))
    }

    /// Takes the bars down and forgets the groups; windows stay where they are (tab groups design 4.7).
    func stop() {
        run += 1
        for task in forwarding { task.cancel() }
        forwarding = []
        inputTask?.cancel()
        inputTask = nil
        queue?.finish()
        queue = nil
        pendingSettings = nil
        relayoutIncomplete = false
        settle.cancelAll()
        reconcileWork?.cancel()
        reconcileWork = nil
        for task in syncs.values { task.cancel() }
        syncs = [:]
        presenter.hideAll()
        book = TabBook()
        infos = [:]
        written = [:]
        writing = [:]
        pendingWrites = [:]
        heightAdjustedWindows = []
        undone = [:]
        answers = [:]
        earlierAnswers = [:]
        placements = [:]
        rested = [:]
        userMoved = []
        lastSeen = [:]
        lastGesture = nil
        appearedAt = [:]
        dropPreview = nil
        draggedItem = nil
        liftedBar = nil
        tabDrag = nil
        lastUsed = [:]
        refused = [:]
        drag = JoinDragTracker()
        let dropped = backlog
        backlog = []
        for event in dropped { Self.drop(event) }
    }

    func apply(_ settings: TabGroupsSettings) {
        // Initial settings must survive start(), which clears the queue and the groups.
        if !isRunning, book.all.isEmpty { updateSettings(settings); return }
        let alreadyQueued = pendingSettings != nil
        pendingSettings = settings
        if !alreadyQueued { submit(.settings) }
    }

    private func updateSettings(_ settings: TabGroupsSettings) {
        let old = self.settings
        self.settings = settings
        if old.joinsByCommandDrag != settings.joinsByCommandDrag || old.mergesOnSnap != settings.mergesOnSnap {
            subscribeInput()
        }
        if !settings.joinsByCommandDrag {
            drag = JoinDragTracker()
            if dropPreview != nil { setDropPreview(nil) }
        }
    }

    func loadDisplays() async {
        displays = await windows.displays()
    }

    func submit(_ event: Event) {
        if let queue { queue.yield(event) } else { backlog.append(event) }
    }

    /// Tests: handles, in order, what was submitted while the controller was not started.
    func drain() async {
        while !backlog.isEmpty { await process(backlog.removeFirst()) }
    }

    /// Runs `job` behind everything already queued, or at once when the controller is not started.
    func serially(_ job: @escaping @MainActor @Sendable () async -> CommandResult) async -> CommandResult {
        guard let queue else { return await job() }
        return await withCheckedContinuation { continuation in queue.yield(.job(job, continuation)) }
    }

    /// The groups for other modules, read behind everything already queued: a job that regroups
    /// windows holds them in no group for the length of several writes, and a read in between
    /// would miss the group. Read at once when the controller is not started.
    func snapshotsInTurn() async -> [TabGroupSnapshot] {
        guard let queue else { return snapshots }
        return await withCheckedContinuation { continuation in queue.yield(.snapshots(continuation)) }
    }

    var isRunning: Bool { queue != nil }

    func process(_ event: Event) async {
        switch event {
        case .window(let event): await handle(event)
        case .input(let event): await handle(event)
        case .settled(let id): await settled(id)
        case .reconcile: await reconcile()
        case .bar(let action): await handle(action)
        case .settings:
            // Inactive tabs may still be following a drag. Finish those writes under the old
            // height before changing the geometry used to interpret their reports.
            await finishSyncs()
            guard let settings = pendingSettings else { return }
            pendingSettings = nil
            let oldHeight = barHeight
            updateSettings(settings)
            if oldHeight != barHeight || relayoutIncomplete { await relayout() }
        case .placing(let request): placing(request)
        case .job(let job, let continuation): continuation.resume(returning: await job())
        case .snapshots(let continuation): continuation.resume(returning: snapshots)
        }
    }

    /// What waits for an answer in a queue that stopped still gets one: a stopped module has no groups.
    private static func drop(_ event: Event) {
        switch event {
        case .job(_, let continuation): continuation.resume(returning: .unavailable(reason: stoppedReason))
        case .snapshots(let continuation): continuation.resume(returning: [])
        case .window, .input, .settled, .reconcile, .bar, .settings, .placing: break
        }
    }

    private func subscribeInput() {
        inputTask?.cancel()
        inputTask = nil
        // Merging on snap watches clicks and the leader key to tell the user's moves from an app's;
        // a tab drag follows the mouse and ends when it comes up.
        guard queue != nil else { return }
        let events = input.events([.mouseButtons, .modifiers, .leader])
        inputTask = Task { [weak self] in for await event in events { self?.submit(.input(event)) } }
    }

    // MARK: Window events

    private func handle(_ event: WindowEvent) async {
        switch event {
        case .moved(let id, let frame), .resized(let id, let frame):
            await windowChanged(id, to: frame)
        case .focused(let id):
            focused(id)
        case .disappeared(let id), .minimized(let id):
            await apply(drag.windowGone(id))
            settle.forget(id)
            userMoved.remove(id)
            written[id] = nil
            pendingWrites[id] = nil
            heightAdjustedWindows.remove(id)
            undone[id] = nil
            answers[id] = nil
            earlierAnswers[id] = nil
            placements[id] = nil
            appearedAt[id] = nil
            lastSeen[id] = nil
            refused[id] = nil
            await leave(id)
        case .titleChanged(let id, let title):
            guard infos[id] != nil, let group = book.group(containing: id) else { return }
            infos[id]?.title = title
            showBar(group.id)
        case .appTerminated(let pid):
            for id in infos.values.filter({ $0.pid == pid }).map(\.id) { await leave(id) }
        case .displaysChanged:
            await loadDisplays()
            scheduleReconcile()
        case .currentSpaceChanged:
            await desktopChanged()
            scheduleReconcile()
        case .spacesChanged:
            // A desktop that is gone took its groups' windows to a neighbour: the check that
            // follows finds them there. The bars wait for it, since which desktop shows is as before.
            scheduleReconcile()
        case .exposeChanged(let isShowing):
            // Mission Control, App Exposé and Show Desktop leave the bars drawn where they are.
            presenter.setHidden(isShowing)
        case .appHidden, .appUnhidden:
            scheduleReconcile()
        case .appeared(let info):
            let now = scheduler.now
            appearedAt = appearedAt.filter { now - $0.value < Self.newWindowGrace }
            appearedAt[info.id] = now
        case .restored, .appLaunched:
            break
        }
    }

    /// 4.4: a group's active window carries the bar and the other tabs with it; any window the
    /// user moved is looked at again once it comes to rest.
    func windowChanged(_ id: WindowID, to frame: CGRect) async {
        guard lastSeen.updateValue(frame, forKey: id) != frame else { return }
        // Writes already update infos from their readback. Replaying an older notification here
        // would replace that newer state and take the bar's height from the group a second time.
        let undoneWrite = undone.removeValue(forKey: id)
        let echo = acknowledgesWrite(id, frame) || isEcho(id, frame)
            || undoneWrite.map { TabGeometry.same($0, frame) } == true
        guard !echo else { return }
        if heightAdjustedWindows.contains(id), book.group(containing: id) != nil,
           let current = await windows.window(id), current.frame != frame {
            log.trace("\(id) 忽略过时的高度调整通知 \(Self.text(frame))，当前 \(Self.text(current.frame))")
            return
        }
        heightAdjustedWindows.remove(id)
        if infos[id] != nil { infos[id]?.frame = frame }
        written[id] = nil
        pendingWrites[id] = nil
        if settings.joinsByCommandDrag { await apply(drag.windowMoved(id, to: frame, zones: joinZones())) }
        let byUser = isUserMove(id)
        if byUser { lastGesture = scheduler.now }
        if book.group(containing: id) != nil || byUser {
            log.trace("\(id) 移到 \(Self.text(frame))，\(byUser ? "用户" : "应用自己")")
        }
        if let group = book.group(containing: id) {
            guard group.active == id else { return }
            if byUser { userMoved.insert(id) }
            follow(group, to: frame)
            settle.moved(id)
        } else if byUser, settings.mergesOnSnap {
            userMoved.insert(id)
            settle.moved(id)
        }
    }

    /// Whether a move is the user's doing rather than an app placing its own window: it comes
    /// during a drag, while the leader key is held or soon after a click or the leader key, and
    /// not from a window that has only just appeared. A move counted as the user's extends the
    /// gesture, so cycling a layout command keeps counting.
    func isUserMove(_ id: WindowID) -> Bool {
        let now = scheduler.now
        if let appeared = appearedAt[id], now - appeared < Self.newWindowGrace { return false }
        if isLeftButtonDown() || input.isLeaderKeyHeld { return true }
        return lastGesture.map { now - $0 <= Self.gestureWindow } ?? false
    }

    /// Whether the change is Tangler's own write coming back as an event.
    func isEcho(_ id: WindowID, _ frame: CGRect) -> Bool {
        // Compare the actual readback exactly: a real one-point move must still be followed.
        writing[id, default: 0] > 0 || written[id] == frame
    }

    /// Retire writes in report order. Repeated slider values can have the same final frame, so
    /// acknowledge the oldest matching write first. A real move after the acknowledgement is
    /// followed normally, even if it returns to one of the write's intermediate positions.
    func acknowledgesWrite(_ id: WindowID, _ frame: CGRect) -> Bool {
        guard let pending = pendingWrites[id] else { return false }
        if let index = pending.firstIndex(where: { $0.to == frame }) {
            let remaining = Array(pending.dropFirst(index + 1))
            pendingWrites[id] = remaining.isEmpty ? nil : remaining
            return true
        }
        return pending.contains { write in
            guard let from = write.from else { return false }
            return frame == CGRect(origin: from.origin, size: write.to.size)
                || frame == CGRect(origin: write.to.origin, size: from.size)
        }
    }

    /// While the active window moves, the bar rides just above it, never above the visible area,
    /// and the other tabs stay behind it. The group's area moves along at once, not only when the
    /// window comes to rest: the active window may close or leave first (tab groups design 11), and
    /// anything that redraws the bar meanwhile must draw it where the windows are. A report that
    /// leaves the area where it is and finds the other tabs at its frame, as the answer to Tangler's
    /// own write does, moves nothing.
    func follow(_ group: TabGroup, to frame: CGRect) {
        // A window going full screen leaves the group once it comes to rest; the others stay put.
        guard !displays.contains(where: { TabGeometry.same($0.frame, frame) }) else { return }
        rested[group.id] = (group.active, areaAtRest(of: group))
        let (frame, area) = resting(group, at: frame)
        let stays = area == group.area
        if !stays {
            book.setArea(area, displayID: display(around: frame)?.id ?? group.displayID, of: group.id)
            showBar(group.id)
        }
        for member in group.members where member != group.active {
            // Under a bar stopped at the visible top the window moves and the area does not: the
            // other tabs go where the window is all the same, unless they are there already.
            if stays, let known = infos[member]?.frame, TabGeometry.same(intended(known, of: member, in: area), frame) { continue }
            syncs[member] = Task { [weak self] in _ = await self?.write(member, frame) }
        }
    }

    /// Where the group is when its window in front is at `frame`: the frame it goes by, and its
    /// area. Where the layout put the window, both are what the layout asked, not what is read off
    /// the window: asked into a place, the group fills exactly that place, bar inside its top; asked
    /// to take its own frame somewhere, the window carries the bar above it. Any other change is
    /// told apart by its frames (`TabGeometry.area(following:)`): the frame now, against the area
    /// the group had when this window last rested. While the window moves, `follow` has the area
    /// move along, and where the bar stops at the visible top that area is no longer the window's
    /// frame plus the bar: against it a window only dragged would look resized, and so placed.
    func resting(_ group: TabGroup, at frame: CGRect) -> (frame: CGRect, area: CGRect) {
        if let asked = placement(of: group.active, at: frame) {
            guard !asked.isZone else { return (asked.frame, asked.frame) }
            return (asked.frame, TabGeometry.area(forWindowAt: asked.frame, visibleTop: visibleTop(around: asked.frame),
                                                  barHeight: barHeight))
        }
        let frame = intended(frame, of: group.active, in: group.area)
        return (frame, TabGeometry.area(following: frame, rested: areaAtRest(of: group), visibleTop: visibleTop(around: frame),
                                        barHeight: barHeight))
    }

    /// The group's area as it was when its window in front last rested: the area it has, unless
    /// that window is on the move.
    func areaAtRest(of group: TabGroup) -> CGRect {
        rested[group.id].flatMap { $0.front == group.active ? $0.area : nil } ?? group.area
    }

    /// The frame the group goes by when `id` is at `frame`: the frame itself, unless the window's
    /// application took another size than the one Tangler wrote (`TabGeometry.intended`).
    func intended(_ frame: CGRect, of id: WindowID, in area: CGRect) -> CGRect {
        guard let answer = answers[id] else { return frame }
        return TabGeometry.intended(frame, asked: answer.asked, took: answer.took,
                                    memberTop: TabGeometry.memberFrame(of: area, barHeight: barHeight).minY, barHeight: barHeight)
    }

    /// The layout is about to ask a window to take a frame. A place to fill is kept as asked. The
    /// window's own frame, centred or sent back where it was, is one the layout read off the window:
    /// at a size the window took of one of Tangler's writes, it stands for the size written.
    func placing(_ request: PlacementRequest) {
        var frame = request.frame
        if !request.isZone {
            let known = (answers[request.windowID].map { [$0] } ?? []) + earlierAnswers[request.windowID, default: []]
            let size = CGRect(origin: .zero, size: frame.size)
            if let answer = known.first(where: { TabGeometry.sameSize(CGRect(origin: .zero, size: $0.took), size) }) {
                frame.size = answer.asked
            }
        }
        placements[request.windowID] = (frame, request.isZone)
    }

    /// The frame the layout asked `id` to take, while the window at `frame` is at what it made of
    /// it (`TabGeometry.takesPlace`): the zone, where an application that sizes its windows in steps
    /// took a size of its own. nil when the layout asked nothing, or the window is elsewhere.
    func placement(of id: WindowID, at frame: CGRect) -> (frame: CGRect, isZone: Bool)? {
        guard let asked = placements[id], TabGeometry.takesPlace(frame, of: asked.frame, pushedBack: true) else { return nil }
        return asked
    }

    /// Waits for the live writes, so a late one cannot undo a final placement.
    func finishSyncs() async {
        let pending = Array(syncs.values)
        syncs = [:]
        for task in pending { await task.value }
    }

    private func focused(_ id: WindowID) {
        guard let group = book.group(containing: id) else { return }
        log.trace("\(id) 获得焦点，\(group.id) 原来的当前标签是 \(group.active)")
        if group.active != id {
            book.activate(id)
            showBar(group.id)
        }
        markUsed(group.id)
        reorderBar(group.id, above: id)
    }

    func markUsed(_ groupID: TabGroupID) {
        useCount += 1
        lastUsed[groupID] = useCount
    }

    /// Groups on screen, the most recently used first: where bars overlap, that one is in front.
    var groupsByUse: [TabGroup] {
        book.all.filter { isOnScreen($0) }.sorted { lastUsed[$0.id, default: 0] > lastUsed[$1.id, default: 0] }
    }

    /// The bar height changed: each group keeps its place, its windows give the bar its new room.
    private func relayout() async {
        relayoutIncomplete = true
        let run = self.run
        let height = barHeight
        let groups = book.all
        // Repaint every bar in this main-actor turn, before awaiting any external app.
        for group in groups {
            rested[group.id] = nil
            showBar(group.id)
        }
        let visible = groups.map { ($0.active, TabGeometry.memberFrame(of: $0.area, barHeight: height)) }
        let background = groups.flatMap { group in
            group.members.filter { $0 != group.active }.map {
                ($0, TabGeometry.memberFrame(of: group.area, barHeight: height))
            }
        }
        // Start each app independently, with its visible tabs first. Keep only one write per
        // app in flight so a newer height can skip that app's remaining obsolete work.
        let byApp = Dictionary(grouping: visible + background, by: { infos[$0.0]?.pid })
        let completed = await withTaskGroup(of: Bool.self, returning: Bool.self) { tasks in
            for requests in byApp.values {
                tasks.addTask { @MainActor in
                    for (id, member) in requests {
                        guard self.run == run else { return false }
                        if let next = self.pendingSettings, next.effectiveBarHeight != height { return false }
                        self.heightAdjustedWindows.insert(id)
                        await self.write(id, member)
                    }
                    return true
                }
            }
            var completed = true
            for await result in tasks { if !result { completed = false } }
            return completed
        }
        if self.run == run { relayoutIncomplete = !completed }
    }

    private func settled(_ id: WindowID) async {
        let byUser = userMoved.remove(id) != nil
        log.trace("\(id) 停稳\(byUser ? "（用户移动）" : "")")
        if let group = book.group(containing: id) {
            guard group.active == id else { return }
            await finalize(group.id)
            if byUser, settings.mergesOnSnap { await mergeOnSnap(group: group.id) }
            return
        }
        if byUser, settings.mergesOnSnap { await mergeOnSnap(window: id) }
        // At rest somewhere else than the layout put it, it is no longer where it was asked to be.
        if let seen = lastSeen[id], placement(of: id, at: seen) == nil { placements[id] = nil }
    }

    /// 4.4: the active window came to rest; the bar takes its room and the other tabs line up behind.
    func finalize(_ groupID: TabGroupID) async {
        // At rest: the area set here is the one the next move is measured against.
        defer { rested[groupID] = nil }
        await finishSyncs()
        guard let group = book.group(groupID) else { return }
        guard let active = await windows.window(group.active), !active.isMinimized, !active.isFullscreen else {
            await leave(group.active)
            return
        }
        infos[active.id] = active
        let (frame, area) = resting(group, at: active.frame)
        // The group has taken the place the layout asked for; from here on it goes by its own writes.
        placements[active.id] = nil
        book.setArea(area, displayID: active.displayID, of: groupID)
        log.trace("\(groupID) 落定：当前标签 \(active.id) 在 \(Self.text(active.frame))，区域 \(Self.text(area))")
        let member = TabGeometry.memberFrame(of: area, barHeight: barHeight)
        if !TabGeometry.same(frame, member) { await write(active.id, member) }
        for id in group.members where id != active.id {
            if let known = infos[id]?.frame, TabGeometry.same(intended(known, of: id, in: area), member) { continue }
            await write(id, member)
        }
        showBar(groupID)
        reorderBar(groupID, above: active.id)
    }

    // MARK: Keeping groups true to the windows

    func scheduleReconcile() {
        reconcileWork?.cancel()
        reconcileWork = scheduler.schedule(at: scheduler.now + Self.reconcileDelay) { [weak self] in
            self?.reconcileWork = nil
            self?.submit(.reconcile)
        }
    }

    /// 4.6: drops windows that left, and takes the window in front of each group's area as its
    /// active tab, so Dock clicks, ⌘Tab and Mission Control never leave a stale highlight.
    func reconcile() async {
        currentSpaces = Set(await windows.spaces().filter(\.isCurrent).map(\.id))
        for group in book.all {
            await settleSpaces(of: group)
            // A group whose Space is not showing waits: its windows may not even be listed now.
            guard let group = book.group(group.id), isOnScreen(group) else { continue }
            for id in group.members where book.group(containing: id)?.id == group.id {
                guard let info = await windows.window(id), !info.isMinimized, !info.isFullscreen else {
                    await leave(id)
                    continue
                }
                infos[id] = info
            }
            guard let fresh = book.group(group.id) else { continue }
            log.trace("检查 \(fresh.id)：成员 \(fresh.members.map(\.rawValue))，区域 \(Self.text(fresh.area))")
            let member = TabGeometry.memberFrame(of: fresh.area, barHeight: barHeight)
            if let top = await windows.windowID(at: CGPoint(x: member.midX, y: member.midY)),
               top != fresh.active, fresh.members.contains(top) {
                book.activate(top)
            }
            // A hidden app's window is not on screen: another tab shows in its place.
            if let shown = book.group(fresh.id), isHidden(shown.active),
               let visible = shown.members.first(where: { !isHidden($0) }) {
                book.activate(visible)
            }
            showBar(fresh.id)
            if let active = book.group(fresh.id)?.active { reorderBar(fresh.id, above: active) }
        }
    }

    /// macOS reports a desktop switch only once its animation has ended, about half a second after
    /// the keys (tab groups design 11), so bars cannot wait for it: each lives on its group's Space
    /// and slides away and back with it. Here the bars of the groups now showing are brought up to
    /// date, and a group that came here without its bar gets one.
    func desktopChanged() async {
        currentSpaces = Set(await windows.spaces().filter(\.isCurrent).map(\.id))
        for group in book.all where isOnScreen(group) {
            showBar(group.id)
            reorderBar(group.id, above: group.active)
        }
    }

    /// Puts the group's bar back just above `window`, only while the group's Space shows: a bar
    /// on another Space has nothing to be ordered against here.
    func reorderBar(_ groupID: TabGroupID, above window: WindowID) {
        guard let group = book.group(groupID), isOnScreen(group) else { return }
        presenter.reorder(groupID, above: window)
    }

    /// 4.6: where the group's windows are now. All of them on one other Space: the group was taken
    /// there, to another display say, and lives there now. Otherwise the windows found on another
    /// Space were moved away one by one, and leave. A window whose Space is unknown counts for neither.
    private func settleSpaces(of group: TabGroup) async {
        guard let home = group.spaceID else { return }
        var elsewhere: [WindowID: SpaceID] = [:]
        var known = 0
        for id in group.members {
            guard let info = await windows.window(id), info.spaceIDs.count == 1, let space = info.spaceIDs.first else {
                continue
            }
            known += 1
            if space != home { elsewhere[id] = space }
        }
        guard !elsewhere.isEmpty else { return }
        let spaces = Set(elsewhere.values)
        if known == group.members.count, elsewhere.count == known, spaces.count == 1, let space = spaces.first {
            log.trace("\(group.id) 整组到了 \(space)")
            book.setSpace(space, of: group.id)
            // Its bar is on the Space it left; it comes back on the new one when that Space shows.
            presenter.hide(group.id)
        } else {
            for id in group.members where elsewhere[id] != nil { await leave(id) }
        }
    }

    func isOnScreen(_ group: TabGroup) -> Bool {
        guard let space = group.spaceID, !currentSpaces.isEmpty else { return true }
        return currentSpaces.contains(space)
    }

    // MARK: Tabs

    /// 4.5: shows `id`'s tab: in place, highlighted, focused alone, the bar just above it.
    func activate(_ id: WindowID, in groupID: TabGroupID) async -> CommandResult {
        guard let group = book.group(groupID), group.members.contains(id) else {
            return .failed(reason: L10n.text("tabgroups.this.window.is.not.in.a.tab"))
        }
        markUsed(groupID)
        let member = TabGeometry.memberFrame(of: group.area, barHeight: barHeight)
        if let known = infos[id]?.frame, !TabGeometry.same(intended(known, of: id, in: group.area), member) {
            await write(id, member)
        }
        book.activate(id)
        showBar(groupID)
        switch await windows.focus(id) {
        case .success:
            reorderBar(groupID, above: id)
            return .done
        case .failure(let error):
            log.problem("切到 \(id) 失败：\(error)")
            scheduleReconcile()
            return .failed(reason: Self.text(for: error))
        }
    }

    /// 4.6 and 4.7: the window is no longer in its group. A group left with one window ends and
    /// gives that window the whole area back. Not so when the caller is about to place that window
    /// (`placing`): written twice in one job, it would have both writes reported once the job is
    /// over, and the first report, no longer the last write, would pass for a move of its own and
    /// take its new group along. The caller gets the window and the area it is owed, to put it
    /// there should it not be placed after all.
    @discardableResult
    func leave(_ id: WindowID, placing: Set<WindowID> = []) async -> (window: WindowID, area: CGRect)? {
        infos[id] = nil
        heightAdjustedWindows.remove(id)
        endTabDrag(of: id)
        guard let groupID = book.group(containing: id)?.id else { return nil }
        log.trace("\(id) 离开 \(groupID)")
        switch book.remove(id) {
        case .notMember:
            return nil
        case .removed(let rest):
            showBar(groupID)
            reorderBar(groupID, above: rest.active)
            // The window now in front may not be the one the book chose.
            scheduleReconcile()
            return nil
        case .dissolved(let group, let remaining):
            // The bar the other window's tab was dragged from is gone. Left open, the drag would
            // end in whatever group that window is put in next, and move its tab there.
            endTabDrag(of: remaining)
            presenter.hide(group.id)
            forgetPreview(of: group.id)
            infos[remaining] = nil
            heightAdjustedWindows.remove(remaining)
            guard !placing.contains(remaining) else { return (remaining, group.area) }
            await write(remaining, group.area)
            return nil
        }
    }

    /// Ends the drag of `id`'s tab without moving anything, its small tab and its preview included:
    /// the tab is no longer in the group it was dragged in.
    private func endTabDrag(of id: WindowID) {
        guard tabDrag?.tab == id else { return }
        tabDrag = nil
        setDropPreview(nil)
        presenter.showGhost(nil, at: .zero)
    }

    /// Shows the group's bar, or takes it down while every tab's app is hidden. A bar lives on its
    /// group's Space: while another Space shows, one that is up only takes the new content, and none
    /// is put up, since it would land on the Space showing now.
    func showBar(_ groupID: TabGroupID) {
        guard let group = book.group(groupID), group.members.contains(where: { !isHidden($0) }) else {
            return presenter.hide(groupID)
        }
        let frame = TabGeometry.barFrame(of: group.area, barHeight: barHeight)
        if isOnScreen(group) {
            presenter.show(content(of: group), frame: frame, above: group.active, onAction: onAction)
        } else {
            presenter.update(content(of: group), frame: frame)
        }
    }

    func isHidden(_ id: WindowID) -> Bool { infos[id].map { isAppHidden($0.pid) } ?? false }

    func content(of group: TabGroup) -> TabBarContent {
        let tabs = group.members.map { id -> TabItem in
            let info = infos[id]
            return TabItem(id: id, title: info?.title ?? "", appName: info?.appName ?? "", pid: info?.pid ?? 0,
                           bundleID: info?.bundleID, isActive: id == group.active,
                           isHidden: isHidden(id))
        }
        let incoming = dropPreview.flatMap { $0.group == group.id ? IncomingTab(tab: $0.tab, slot: $0.slot) : nil }
        let leaving = (tabDrag?.tab).flatMap { group.members.contains($0) && dropPreview?.group != group.id ? $0 : nil }
        return TabBarContent(group: group.id, tabs: tabs, incoming: incoming, leaving: leaving)
    }

    // MARK: Windows and displays

    /// Moves a window, remembering the write so its echo is not taken for the user's move.
    @discardableResult
    func write(_ id: WindowID, _ frame: CGRect) async -> Result<CGRect, WindowError> {
        let from = infos[id]?.frame ?? lastSeen[id]
        written[id] = frame
        placements[id] = nil
        writing[id, default: 0] += 1
        let result = await windows.setFrame(id, to: frame, animation: .none)
        log.trace("写入 \(id) → \(Self.text(frame))：\((try? result.get()).map(Self.text) ?? "失败")")
        writing[id, default: 1] -= 1
        if writing[id] == 0 { writing[id] = nil }
        if case .success(let actual) = result {
            // Bound history for apps that never acknowledge writes. Unknown external frames
            // clear it immediately; ordinary acknowledgements retire it in windowChanged.
            pendingWrites[id] = Array((pendingWrites[id, default: []] + [(from, actual)]).suffix(32))
            written[id] = actual
            if let last = answers[id] {
                earlierAnswers[id] = Array(([last] + earlierAnswers[id, default: []]).prefix(Self.answersKept))
            }
            answers[id] = actual.size == frame.size ? nil : (frame.size, actual.size)
            if infos[id] != nil { infos[id]?.frame = actual }
        }
        return result
    }

    /// Undoes a write made earlier in the same job. Both writes are reported once the job is over,
    /// when the first is no longer the last one written: it is remembered, or its report would pass
    /// for the user's move and merging on snap would group the window with whatever it rests on.
    func putBack(_ id: WindowID, to frame: CGRect) async {
        undone[id] = written[id]
        await write(id, frame)
    }

    /// The display holding `rect`'s center, else the one it overlaps most, else the nearest.
    func display(around rect: CGRect) -> DisplayInfo? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        if let holding = displays.first(where: { $0.frame.contains(center) }) { return holding }
        func overlap(_ display: DisplayInfo) -> CGFloat {
            let shared = display.frame.intersection(rect)
            return shared.isNull ? 0 : shared.width * shared.height
        }
        func distance(_ display: DisplayInfo) -> CGFloat {
            hypot(display.frame.midX - center.x, display.frame.midY - center.y)
        }
        if let most = displays.max(by: { overlap($0) < overlap($1) }), overlap(most) > 0 { return most }
        return displays.min { distance($0) < distance($1) }
    }

    /// The top of the visible area where `rect` is; no limit when the displays are unknown.
    func visibleTop(around rect: CGRect) -> CGFloat {
        display(around: rect)?.visibleFrame.minY ?? -CGFloat.greatestFiniteMagnitude
    }

    static func text(_ rect: CGRect) -> String {
        "(\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))×\(Int(rect.height)))"
    }

    static func text(for error: WindowError) -> String {
        switch error {
        case .notAuthorized: return L10n.text("commandpalette.accessibility.access.is.required")
        case .windowNotFound: return L10n.text("tabgroups.the.window.could.not.be.found.it")
        case .appNotResponding: return L10n.text("commandpalette.the.application.is.not.responding")
        case .rejected(let reason), .unsupported(let reason): return reason
        }
    }
}
