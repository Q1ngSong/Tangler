import Contracts
import CoreKit
import CoreGraphics

/// Opens switchers. Between switches it keeps the window catalog current from window
/// events, so a switcher opens from what is already known instead of waiting for a scan.
@MainActor
final class SwitcherController {
    /// What one switcher lists and where it goes.
    private struct Listing {
        var windows: [WindowInfo] = []
        var focused: WindowID?
        var notices: [String] = []
        /// Why nothing is listed.
        var emptyReason = SwitcherText.noWindows
        var area = CGRect.zero
    }

    private let windows: any WindowService
    private let input: any InputService
    private let capture: any CaptureService
    private let environment: SwitcherEnvironment
    var settings = SwitcherSettings.defaultValue
    private(set) var catalog = WindowCatalog()
    /// The open switcher, from the shortcut press until the choice.
    private(set) var session: SwitcherSession?
    /// Where the open switcher is shown, in global coordinates.
    private var area = CGRect.zero
    private var tasks: [Task<Void, Never>] = []
    private let log = DiagnosticLog("switcher")

    init(windows: any WindowService, input: any InputService, capture: any CaptureService,
         environment: SwitcherEnvironment) {
        self.windows = windows
        self.input = input
        self.capture = capture
        self.environment = environment
    }

    func start() {
        // Subscribe before scanning, so no change in between is lost.
        let events = windows.events()
        tasks = [
            Task { [weak self] in
                for await event in events { self?.windowChanged(event) }
            },
            Task { [weak self] in await self?.rescan() },
        ]
    }

    func stop() {
        session?.cancel()
        for task in tasks { task.cancel() }
        tasks.removeAll()
    }

    /// Runs one switcher until the user chooses a window, which then gets focus, or cancels.
    func open(_ request: SwitcherRequest) async -> CommandResult {
        if let session {
            log.trace("切换器已打开，\(request.reverse ? "后退" : "前进")一格")
            session.step(request.reverse ? .backward : .forward)
            return .done
        }
        log.trace("打开切换器：\(request.kind)\(request.reverse ? "，反向" : "")，快捷键 \(request.chord.map(String.init(describing:)) ?? "无")")
        guard windows.isAuthorized else { return .unavailable(reason: SwitcherText.needsAccessibility) }
        // Take the keyboard and listen for the release first: the user may press Tab again
        // or let go of Command at any moment from here on.
        let events = input.events([.modifiers, .mouseButtons])
        let hold = HoldModifiers(chord: request.chord)
        let session = SwitcherSession(capture: input.beginKeyCapture(),
                                      keys: SwitcherKeys(trigger: request.chord?.key ?? request.kind.defaultTrigger),
                                      hold: hold)
        self.session = session
        session.onFinish = { [weak self, weak session] _ in self?.ended(session) }

        let listing = await load(request)
        let held = !hold.isReleased(in: environment.heldModifiers())
        log.trace("切换器列出 \(listing.windows.count) 个窗口，修饰键\(held ? "还按着，显示面板" : "已松开，直接切换")\(session.isFinished ? "；会话已结束" : "")")
        guard !session.isFinished else { return .done }
        guard !listing.windows.isEmpty else {
            session.cancel()
            return .unavailable(reason: listing.emptyReason)
        }
        present(session, listing: listing, reverse: request.reverse, events: events, showing: held)

        guard case .chosen(let id) = await session.result() else {
            log.trace("切换器取消")
            return .done
        }
        log.trace("切换到窗口 \(id.rawValue)")
        catalog.noteFocus(id)
        switch await windows.focus(id) {
        case .success: return .done
        case .failure(let error): return .failed(reason: SwitcherText.reason(for: error))
        }
    }

    /// Starts the session on its list. Without `showing`, the shortcut was already let go:
    /// the switch happens at once and no panel flashes up.
    private func present(_ session: SwitcherSession, listing: Listing, reverse: Bool,
                         events: AsyncStream<InputEvent>, showing: Bool) {
        let start = SwitcherScope.startIndex(in: listing.windows, focused: listing.focused, reverse: reverse)
        let model = SwitcherModel(windows: listing.windows, selectedIndex: start, notices: listing.notices,
                                  previewHeight: settings.effectivePreviewHeight, maxStripWidth: listing.area.width)
        model.actions = actions(for: session)
        area = listing.area
        let presenter = environment.presenter
        session.isOnPanel = { presenter.visibleFrame?.contains($0) ?? false }
        session.begin(with: model, events: events)
        guard showing else {
            session.chooseAfterPendingKeys()
            return
        }
        let feed = ThumbnailFeed(capture: capture, pixelSize: SwitcherLayout.thumbnailPixelSize(previewHeight: model.previewHeight),
                                 pause: environment.pause) { [weak model] id, image, live in
            model?.setImage(image, for: id, live: live)
        }
        session.onSelectionChange = { feed.follow($0) }
        session.onFinish = { [weak self, weak session] _ in
            feed.stop()
            self?.ended(session)
        }
        presenter.show(model, in: listing.area)
        feed.loadStills(Self.stillOrder(model))
        feed.follow(model.selected?.id)
    }

    private func ended(_ session: SwitcherSession?) {
        guard let session, self.session === session else { return }
        self.session = nil
        environment.presenter.hide()
    }

    private func load(_ request: SwitcherRequest) async -> Listing {
        var listing = Listing()
        let listsOtherSpaces = windows.capabilities.contains(.otherSpaceWindows)
        var spaces: Set<SpaceID>?
        if !listsOtherSpaces {
            let current = await windows.spaces().filter(\.isCurrent).map(\.id)
            spaces = current.isEmpty ? nil : Set(current)
        }
        // Nothing reports a window changing Spaces, so filtering by Space needs a fresh scan.
        if !catalog.isPrimed || catalog.windows.isEmpty || spaces != nil { await rescan() }
        listing.focused = await windows.focusedWindowID()
        if let focused = listing.focused { catalog.noteFocus(focused) }

        var pid: Int32?
        if request.kind == .appWindows {
            listing.emptyReason = SwitcherText.noAppWindows
            guard let focused = listing.focused else { return listing }
            pid = catalog.window(focused)?.pid
            if pid == nil { pid = await windows.window(focused)?.pid }
            guard pid != nil else { return listing }
        }
        let scope = SwitcherScope(pid: pid, spaces: spaces, includeMinimized: settings.includeMinimized)
        listing.windows = scope.windows(from: catalog.windows)
        if !capture.isAuthorized { listing.notices.append(SwitcherText.noScreenRecording) }
        if !listsOtherSpaces {
            listing.notices.append(SwitcherText.currentSpaceOnly(reason: windows.unavailableReason(for: .otherSpaceWindows)))
        }

        let pointer = environment.pointer()
        listing.area = SwitcherLayout.area(for: pointer, in: await windows.displays())
            ?? CGRect(x: pointer.x - 600, y: pointer.y - 400, width: 1200, height: 800)
        return listing
    }

    private func rescan() async {
        guard windows.isAuthorized else { return }
        catalog.replace(with: await windows.windows())
    }

    private func windowChanged(_ event: WindowEvent) {
        catalog.apply(event)
        guard let session, let model = session.model else { return }
        switch event {
        case .disappeared(let id):
            if session.windowGone(id) { relayout(session) }
        case .appTerminated(let pid):
            var removed = false
            for item in model.items where item.window.pid == pid {
                removed = session.windowGone(item.id) || removed
            }
            if removed { relayout(session) }
        case .titleChanged(let id, let title):
            model.item(id)?.window.title = title
        case .minimized(let id):
            model.item(id)?.window.isMinimized = true
        case .restored(let id):
            model.item(id)?.window.isMinimized = false
        case .appeared, .moved, .resized, .focused, .currentSpaceChanged, .spacesChanged, .displaysChanged,
             .exposeChanged, .appLaunched, .appHidden, .appUnhidden:
            break
        }
    }

    /// Fits the panel to the cards left after one went away.
    private func relayout(_ session: SwitcherSession) {
        guard self.session === session, let model = session.model,
              environment.presenter.visibleFrame != nil else { return }
        environment.presenter.show(model, in: area)
    }

    private func actions(for session: SwitcherSession) -> SwitcherModel.Actions {
        SwitcherModel.Actions(
            hover: { [weak session] id in session?.select(id) },
            choose: { [weak session] id in session?.choose(id) })
    }

    /// The selected window first, then the ones after it, the way the user is likely to look.
    private static func stillOrder(_ model: SwitcherModel) -> [WindowID] {
        let ids = model.items.map(\.id)
        guard let start = model.selectedIndex else { return ids }
        return Array(ids[start...] + ids[..<start])
    }
}
