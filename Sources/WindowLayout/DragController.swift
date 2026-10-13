import AppKit
import Contracts
import CoreGraphics
import CoreKit

/// Shows and hides the snap preview; the real one is an overlay panel.
@MainActor
protocol SnapPreviewPresenter: AnyObject {
    /// From the layout settings: false when "动画时长" is "无动画".
    var animates: Bool { get set }
    /// Whether window ids match the window server's exactly, so the overlay can sit just below
    /// the dragged window; otherwise it floats above every window.
    var ordersBelowWindow: Bool { get set }
    /// From the layout settings, "吸附预览用玻璃": the zone is real glass in a skin that has a
    /// glass zone. The presenter never asks which skin that is.
    var prefersGlass: Bool { get set }
    func show(_ preview: SnapPreview)
    func hide()
}

/// Feeds input, window events and Esc to the `DragTracker` and carries out what it decides.
/// Every event goes through one queue and is handled to the end before the next one, so the
/// tracker sees events in the order they were delivered, even across window lookups. Window
/// moves are handed to the mover's queue and not waited for, so a slow move never holds up
/// the drags after it.
@MainActor
final class DragController {
    enum Event: Sendable {
        case input(InputEvent)
        case window(WindowEvent)
        case key(KeyPress)
        /// Whether the left button was down when checked at `time`, while the preview of press
        /// number `press` showed.
        case buttonChecked(isDown: Bool, at: ContinuousClock.Instant, press: Int)
    }

    private let windows: any WindowService
    private let input: any InputService
    private let mover: WindowMover
    private let presenter: any SnapPreviewPresenter
    private let isLeftButtonDown: () -> Bool
    /// When to check, while the preview shows, that the button is still down.
    private let buttonCheckTicks: () -> AsyncStream<Void>
    private let now: () -> ContinuousClock.Instant
    private var tracker: DragTracker
    /// Bumped by every start and stop. Work of a run that has ended is dropped: events still in
    /// its queue and lookups under way would drive the reset tracker, and a preview they showed
    /// would start a key capture nothing reads.
    private var run = 0
    private var queue: AsyncStream<Event>.Continuation?
    private var forwarding: [Task<Void, Never>] = []
    private var loop: Task<Void, Never>?
    /// The loop of the run `stop()` ended, kept so tests can wait for it to finish.
    private var stoppedLoop: Task<Void, Never>?
    private var capture: (any KeyCapture)?
    private var captureTask: Task<Void, Never>?
    private var buttonChecks: Task<Void, Never>?
    /// The latest restore of a window dragged out of its snapped place.
    private var restoring: (window: WindowID, task: Task<Void, Never>)?
    /// Left-button presses handled so far; a button check counts only for the press it was made in.
    private var presses = 0
    private let log = DiagnosticLog("drag")
    /// When and where the current left-button press arrived, and the window it found, for the trace.
    private var pressedAt: ContinuousClock.Instant?
    private var pressLocation = CGPoint.zero
    private var pressedFrame: CGRect?
    private var tracedDrag = false
    /// Events put in the queue; lets tests tell when events sent through the services wait in it.
    private(set) var receivedEvents = 0
    /// Events handled to the end, lookups included; lets tests wait for events delivered through
    /// the services.
    private(set) var processedEvents = 0

    /// How often a showing preview checks that the button is still down.
    nonisolated static let buttonCheckInterval: Duration = .milliseconds(250)

    init(windows: any WindowService, input: any InputService, mover: WindowMover,
         presenter: any SnapPreviewPresenter, settings: LayoutSettings,
         isLeftButtonDown: @escaping () -> Bool = { NSEvent.pressedMouseButtons & 1 != 0 },
         buttonCheckTicks: @escaping () -> AsyncStream<Void> = DragController.ticks(every: buttonCheckInterval),
         now: @escaping () -> ContinuousClock.Instant = { .now }) {
        self.windows = windows
        self.input = input
        self.mover = mover
        self.presenter = presenter
        self.isLeftButtonDown = isLeftButtonDown
        self.buttonCheckTicks = buttonCheckTicks
        self.now = now
        tracker = DragTracker(settings: settings, displays: [])
        presenter.animates = settings.animation != .none
        presenter.prefersGlass = settings.glassSnapPreview
        presenter.ordersBelowWindow = windows.capabilities.contains(.exactWindowIDs)
    }

    /// A tick every `interval` for as long as the stream is read. Ticks missed while the reader
    /// was held up come as one.
    nonisolated static func ticks(every interval: Duration) -> () -> AsyncStream<Void> {
        {
            AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
                let timer = Task {
                    while (try? await Task.sleep(for: interval)) != nil { continuation.yield() }
                    continuation.finish()
                }
                continuation.onTermination = { _ in timer.cancel() }
            }
        }
    }

    func start() {
        stop()
        let run = self.run
        let (stream, queue) = AsyncStream.makeStream(of: Event.self)
        self.queue = queue
        let inputEvents = input.events([.mouseButtons, .modifiers])
        let windowEvents = windows.events()
        forwarding = [
            Task { [weak self] in for await event in inputEvents { self?.receive(.input(event), into: queue) } },
            Task { [weak self] in for await event in windowEvents { self?.receive(.window(event), into: queue) } },
        ]
        loop = Task { [weak self] in
            // A finished or cancelled stream still hands over the events it holds; the run check drops them.
            for await event in stream {
                guard let self, self.run == run else { return }
                await self.process(event, in: run)
            }
        }
    }

    func stop() {
        run += 1
        forwarding.forEach { $0.cancel() }
        forwarding = []
        if let loop {
            loop.cancel()
            stoppedLoop = loop
        }
        loop = nil
        queue?.finish()
        queue = nil
        endPreview()
        tracker = DragTracker(settings: tracker.settings, displays: tracker.displays)
    }

    /// Waits until the loop of the last stopped run has finished.
    func stoppedLoopEnded() async {
        await stoppedLoop?.value
    }

    /// Waits until the latest restore is done; drops wait in the mover's queue.
    func restoreEnded() async {
        await restoring?.task.value
    }

    func update(settings: LayoutSettings) {
        presenter.animates = settings.animation != .none
        presenter.prefersGlass = settings.glassSnapPreview
        perform(tracker.update(settings: settings))
    }

    func process(_ event: Event) async {
        await process(event, in: run)
    }

    private func process(_ event: Event, in run: Int) async {
        defer { processedEvents += 1 }
        guard run == self.run else { return }
        switch event {
        case .input(let input): await handle(input, in: run)
        case .window(let change): await handle(change, in: run)
        case .key(let press):
            // Only Esc acts. A key says nothing about the release, which may wait behind it in
            // the queue; one that never comes is found by the button checks.
            if press.key == .escape { perform(tracker.escape()) }
        case .buttonChecked(let isDown, let time, let press):
            guard press == presses else { return }
            perform(tracker.buttonChecked(isDown: isDown, at: time))
        }
    }

    private func handle(_ event: InputEvent, in run: Int) async {
        switch event {
        case .mouseDown(let mouse):
            // Only left-button drags move windows; skip the lookups for every other click.
            guard mouse.button == .left else { return }
            presses += 1
            let pressed = now()
            pressedAt = pressed
            tracedDrag = false
            let window = await pressedWindow(at: mouse.location)
            pressLocation = mouse.location
            pressedFrame = window?.frame
            log.trace("按下 \(Self.describe(mouse.location))\(mouse.modifiers.isEmpty ? "" : " \(mouse.modifiers)")：" + (window.map {
                "窗口 \($0.id.rawValue) \(Self.describe($0.frame))\($0.restoreSize == nil ? "" : "，已吸附")"
            } ?? "不是可摆放的窗口") + "，查找用时 \(Self.describe(pressed.duration(to: now())))")
            guard run == self.run else { return }
            perform(tracker.buttonDown(mouse, on: window))
        case .mouseDragged(let mouse):
            if !tracedDrag, mouse.button == .left {
                tracedDrag = true
                log.trace("指针开始拖动\(sincePress)")
            }
            perform(tracker.pointerMoved(mouse))
        case .mouseUp(let mouse):
            guard mouse.button == .left else { return perform(tracker.buttonUp(mouse)) }
            log.trace("松开 \(Self.describe(mouse.location))\(sincePress)，预览\(tracker.isPreviewing ? "开着" : "没开")"
                      + (tracker.pressedWindowID.map { "，窗口 \($0.rawValue) 还没有移动消息" } ?? ""))
            noteUnseenTitleBarDrag(to: mouse.location)
            perform(tracker.buttonUp(mouse))
        case .modifiersChanged(let modifiers):
            if tracker.isPreviewing || tracker.pressedWindowID != nil { log.trace("修饰键 \(modifiers)") }
            perform(tracker.modifiersChanged(modifiers))
        case .leaderTriggered, .shortcut, .mouseMoved, .scroll: break
        }
    }

    private func handle(_ event: WindowEvent, in run: Int) async {
        switch event {
        case .moved(let id, let frame):
            if tracker.pressedWindowID == id || tracker.isPreviewing {
                log.trace("窗口 \(id.rawValue) 移到 \(Self.describe(frame))\(sincePress)")
            }
            // A drag is starting: read the displays now rather than on every click.
            if tracker.pressedWindowID == id {
                let displays = await windows.displays()
                guard run == self.run else { return }
                _ = tracker.update(displays: displays)
            }
            perform(tracker.windowMoved(id, to: frame))
        case .resized(let id, _): perform(tracker.windowResized(id))
        case .disappeared(let id):
            mover.forget(id)
            perform(tracker.windowGone(id))
        case .minimized(let id): perform(tracker.windowGone(id))
        case .displaysChanged:
            let displays = await windows.displays()
            guard run == self.run else { return }
            perform(tracker.update(displays: displays))
        case .appeared, .focused, .restored, .titleChanged, .currentSpaceChanged, .spacesChanged, .exposeChanged,
             .appLaunched, .appTerminated, .appHidden, .appUnhidden:
            break
        }
    }

    /// The window under a left-button press, unless nothing could happen to it: with snapping
    /// and the grid both off only a snapped window, which still gets its size back, is read.
    private func pressedWindow(at point: CGPoint) async -> PressedWindow? {
        guard let id = await windows.windowID(at: point) else { return nil }
        let snapsOnDrag = tracker.settings.edgeSnapping || tracker.settings.grid
        guard snapsOnDrag || mover.memory.snapRecord(for: id) != nil,
              let window = await windows.window(id), !window.isFullscreen, !window.isMinimized else { return nil }
        return PressedWindow(id: id, frame: frameWhenPressed(window, at: point),
                             restoreSize: mover.restoreSize(for: id, at: window.frame))
    }

    /// WindowKit may read the window only after a quick drag has carried it away, but a snapped
    /// window the press landed on was still where Tangler put it. For any other window the
    /// read is the best there is.
    private func frameWhenPressed(_ window: WindowInfo, at point: CGPoint) -> CGRect {
        guard let snapped = mover.memory.snapRecord(for: window.id)?.snappedFrame,
              WindowMemory.sameSize(snapped, window.frame), snapped.contains(point) else { return window.frame }
        return snapped
    }

    /// A restore happens at once: the pointer is holding the window, and its frame is worked out
    /// for where the pointer is now. A drop joins the mover's queue, behind commands and workspace
    /// restores already under way, and waits for the restore of its window.
    private func perform(_ effects: [DragEffect]) {
        for effect in effects {
            log.trace(Self.describe(effect))
            switch effect {
            case .show(let preview):
                presenter.show(preview)
                beginCapture()
            case .hide:
                endPreview()
            case .restoreSize(let id, let frame):
                let mover = self.mover
                restoring = (id, Task { await mover.restoreSize(of: id, to: frame) })
            case .place(let id, let frame, let bounds, let start):
                let windows = self.windows
                let mover = self.mover
                let restore = restoring?.window == id ? restoring?.task : nil
                mover.enqueue {
                    await restore?.value
                    guard let window = await windows.window(id) else { return }
                    _ = await mover.move(window, to: frame, within: bounds, kind: .snap, historyFrame: start)
                }
            case .releasedUnmoved(let id):
                // A snapped window must be known where it is: the next press starts from there.
                guard mover.memory.snapRecord(for: id) != nil else { break }
                let windows = self.windows
                let mover = self.mover
                Task {
                    guard let window = await windows.window(id) else { return }
                    mover.snappedWindow(id, isAt: window.frame)
                }
            }
        }
    }

    /// Esc cancels while the preview shows; the capture keeps the key from the app below. The
    /// button checks run as long as the capture. Each records the button, and the time, when it
    /// runs, and joins the queue behind any release that reached it first.
    private func beginCapture() {
        guard capture == nil else { return }
        let capture = input.beginKeyCapture()
        self.capture = capture
        let queue = self.queue
        captureTask = Task { [weak self] in
            for await press in capture.keys { self?.receive(.key(press), into: queue) }
        }
        let ticks = buttonCheckTicks()
        let isDown = isLeftButtonDown
        let now = self.now
        let press = presses
        buttonChecks = Task { [weak self] in
            for await _ in ticks {
                self?.receive(.buttonChecked(isDown: isDown(), at: now(), press: press), into: queue)
            }
        }
    }

    /// A drag from near a window's top edge that went some way but never saw the window move:
    /// most likely a title-bar drag WindowKit reported too late. Kept in the log, unlike the
    /// trace, so an occasional miss can be looked up afterwards.
    private func noteUnseenTitleBarDrag(to release: CGPoint) {
        guard let id = tracker.pressedWindowID, let frame = pressedFrame,
              hypot(release.x - pressLocation.x, release.y - pressLocation.y) > 30,
              pressLocation.y - frame.minY < 40 else { return }
        log.note("标题栏拖动没被识别：窗口 \(id.rawValue) \(Self.describe(frame))，从 \(Self.describe(pressLocation)) "
                 + "拖到 \(Self.describe(release))\(sincePress)，一直没收到窗口移动的消息")
    }

    /// "，距按下 120ms" while a press is under way.
    private var sincePress: String {
        pressedAt.map { "，距按下 \(Self.describe($0.duration(to: now())))" } ?? ""
    }

    private static func describe(_ point: CGPoint) -> String { "(\(Int(point.x)),\(Int(point.y)))" }

    private static func describe(_ rect: CGRect) -> String {
        "(\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))×\(Int(rect.height)))"
    }

    private static func describe(_ duration: Duration) -> String {
        "\(Int((Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18) * 1000))ms"
    }

    private static func describe(_ effect: DragEffect) -> String {
        switch effect {
        case .show(let preview): return "显示\(preview.gridCells == nil ? "" : "网格")预览 \(describe(preview.target))"
        case .hide: return "隐藏预览"
        case .restoreSize(let id, let frame): return "窗口 \(id.rawValue) 恢复吸附前的大小 \(describe(frame))"
        case .place(let id, let frame, _, _): return "窗口 \(id.rawValue) 摆放到 \(describe(frame))"
        case .releasedUnmoved(let id): return "窗口 \(id.rawValue) 松开时没看到移动，不摆放"
        }
    }

    private func receive(_ event: Event, into queue: AsyncStream<Event>.Continuation?) {
        guard let queue else { return }
        receivedEvents += 1
        queue.yield(event)
    }

    private func endPreview() {
        presenter.hide()
        captureTask?.cancel()
        captureTask = nil
        capture?.end()
        capture = nil
        buttonChecks?.cancel()
        buttonChecks = nil
    }
}
