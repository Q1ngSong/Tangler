import Contracts
import CoreGraphics
import CoreKit

/// Opening, updating and closing the preview, and its cards' buttons.
extension DockPreviewController {
    /// Starts loading the app the machine is about to show.
    func prepare(_ item: DockItem) {
        guard pending?.item.pid != item.pid else { return }
        pending?.cancel()
        pending = startSession(for: item)
    }

    /// Drops the loading app once the machine no longer means to show it.
    func dropAbandonedSession() {
        guard let pending, machine.pending?.pid != pending.item.pid else { return }
        pending.cancel()
        self.pending = nil
    }

    func show(_ item: DockItem) {
        let session: DockPreviewSession
        if let pending, pending.item.pid == item.pid {
            session = pending
            self.pending = nil
        } else {
            session = startSession(for: item)
        }
        session.item = item
        if let shown, shown !== session { shown.cancel() }
        shown = session
        DiagnosticLog("dock").trace("到时间显示「\(item.appName)」，窗口\(session.windows == nil ? "还没列出" : "已列出")，\(session.elapsed)")
        present(session)
    }

    /// Puts the session on screen while the machine still wants it, or closes the preview when
    /// the app has nothing to show.
    func present(_ session: DockPreviewSession) {
        guard session === shown, machine.target?.pid == session.item.pid, let windows = session.windows else { return }
        let enough = session.hasBeenShown || windows.count > 1 || settings.showsSingleWindowApps
        guard !windows.isEmpty, enough else {
            dismiss()
            return
        }
        // Only an empty display list has no area; the reload presents again once it arrives.
        guard let area = DockPreviewGeometry.area(for: session.item, displays: displays) else {
            reloadDisplays()
            return
        }
        let content = DockPreviewContent(item: session.item, windows: windows, thumbnails: session.thumbnails,
                                         notices: notices, area: area.size)
        let frame = presenter.show(content, placement: DockPreviewGeometry.placement(for: session.item, in: area),
                                   actions: actions)
        if !session.hasBeenShown {
            DiagnosticLog("dock").trace("面板出现「\(session.item.appName)」，缩略图 \(session.thumbnails.count)/\(windows.count)，\(session.elapsed)")
        }
        session.hasBeenShown = true
        machine.presented(in: frame)
    }

    /// Closes the preview on the controller's own account, e.g. after a card was chosen.
    func dismiss() {
        machine.dismissed()
        hidePanel()
        scheduleWakeUp()
    }

    func hidePanel() {
        shown?.cancel()
        shown = nil
        presenter.hide()
    }

    func choose(_ id: WindowID) {
        dismiss()
        let windows = self.windows
        track { _ = await windows.focus(id) }
    }

    func closeWindow(_ id: WindowID) {
        let windows = self.windows
        track { [weak self] in
            guard case .success = await windows.close(id) else { return }
            self?.removeCard(id)
        }
    }

    func minimizeWindow(_ id: WindowID) {
        let windows = self.windows
        track { [weak self] in
            guard case .success = await windows.minimize(id) else { return }
            self?.updateCard(id) { $0.isMinimized = true }
        }
    }

    func handle(_ event: WindowEvent) {
        switch event {
        case .disappeared(let id):
            removeCard(id)
        case .minimized(let id):
            updateCard(id) { $0.isMinimized = true }
        case .restored(let id):
            updateCard(id) { $0.isMinimized = false }
        case .titleChanged(let id, let title):
            updateCard(id) { $0.title = title }
        case .appTerminated(let pid):
            if shown?.item.pid == pid { dismiss() }
            refreshShieldSoon()
        case .appLaunched:
            refreshShieldSoon()
        case .displaysChanged:
            if shown != nil { dismiss() }
            reloadDisplays()
            updateShield()
        case .appeared, .moved, .resized, .focused, .currentSpaceChanged, .spacesChanged, .exposeChanged, .appHidden,
             .appUnhidden:
            break
        }
    }

    private func startSession(for item: DockItem) -> DockPreviewSession {
        let session = DockPreviewSession(item: item)
        session.onChange = { [weak self, weak session] in
            guard let self, let session, session === shown else { return }
            present(session)
        }
        let windows = self.windows
        let capture = self.capture
        session.task = track { [weak session] in await session?.load(windows: windows, capture: capture) }
        return session
    }

    private func removeCard(_ id: WindowID) {
        pending?.remove(id)
        guard let shown, shown.remove(id) else { return }
        present(shown)
    }

    private func updateCard(_ id: WindowID, _ change: (inout WindowInfo) -> Void) {
        pending?.update(id, change)
        guard let shown, shown.update(id, change) else { return }
        present(shown)
    }

    private var notices: [String] {
        var notices: [String] = []
        if !capture.isAuthorized { notices.append(L10n.text("dockpreview.enable.screen.recording.to.show.thumbnails")) }
        if !windows.capabilities.contains(.otherSpaceWindows) { notices.append(L10n.text("dockpreview.only.windows.on.the.current.desktop.are")) }
        return notices
    }

    private var actions: DockPreviewActions {
        DockPreviewActions(choose: { [weak self] in self?.choose($0) },
                           close: { [weak self] in self?.closeWindow($0) },
                           minimize: { [weak self] in self?.minimizeWindow($0) })
    }
}
