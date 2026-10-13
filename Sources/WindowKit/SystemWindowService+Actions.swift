import AppKit
import ApplicationServices
import Contracts
import CoreKit

extension SystemWindowService {
    /// Frames are written in whole points, so the readback of a fractional target can lie up
    /// to half a point away from it: compare the two with a tolerance of a point.
    public func setFrame(_ id: WindowID, to frame: CGRect, animation: FrameAnimation) async -> Result<CGRect, WindowError> {
        guard frame.isFiniteRect, frame.width > 0, frame.height > 0 else { return .failure(.rejected(L10n.text("windowkit.the.target.frame.is.invalid"))) }
        guard await prepare() else { return .failure(.notAuthorized) }
        guard let entry = await entry(for: id) else { return .failure(.windowNotFound(id)) }
        let target = FrameTarget(element: entry.handle.element, pid: entry.info.pid, appName: entry.info.appName)
        let outcome = await frames.move(id, target: target, to: frame, duration: Self.duration(of: animation),
                                        fallback: entry.info.frame)
        switch outcome {
        case .settled(let actual, let stamp):
            let displays = displayCache.value
            registry.update(id, fields: .frame, stamp: stamp) { info in
                info.frame = actual
                info.displayID = DisplayLocator.display(for: actual, in: displays)
            }
            return .success(actual)
        case .failed(let error):
            return .failure(healing(error, pid: entry.info.pid))
        case .written:
            return .failure(.rejected(L10n.text("windowkit.could.not.read.back.the.window.frame")))
        }
    }

    public func focus(_ id: WindowID) async -> Result<Void, WindowError> {
        guard await prepare() else { return .failure(.notAuthorized) }
        guard let entry = await entry(for: id) else { return .failure(.windowNotFound(id)) }
        let actions = self.actions
        let element = entry.handle.element
        let pid = entry.info.pid
        let attempt = await run(on: actionQueue) { actions.focus(element, id: id, pid: pid) }
        if let failure = attempt.failure {
            return .failure(healing(failure.windowError(id: id, pid: pid, appName: entry.info.appName), pid: pid))
        }
        if !attempt.precise {
            // Public fallback, also when the precise request was refused at run time: AppKit
            // activation on top of the Accessibility request.
            _ = await MainActor.run { NSRunningApplication(processIdentifier: pid)?.activate(options: []) }
        }
        // Activation is asynchronous; switching Spaces on the way can take a moment.
        for _ in 0..<24 {
            if await run(on: actionQueue, { actions.isFocused(element, pid: pid) }) {
                // A raise sent while the app was still activating does nothing (seen right after a
                // ⌘-drag, tab groups design 11): raise once more now that the window has focus.
                _ = await run(on: actionQueue, { actions.raise(element) })
                registry.setFocused(id)
                return .success(())
            }
            // Not `Task.sleep`, which returns at once in a cancelled task: the checks would be
            // used up before the application could confirm.
            await Self.pause(milliseconds: 25)
        }
        return .failure(.rejected(L10n.text("windowkit.did.not.switch.to.this.window", String(describing: (entry.info.appName)))))
    }

    public func minimize(_ id: WindowID) async -> Result<Void, WindowError> {
        await perform(on: id) { actions, element in actions.minimize(element) }
    }

    public func close(_ id: WindowID) async -> Result<Void, WindowError> {
        await perform(on: id, { actions, element in actions.close(element) }) { [eventQueue] pid in
            eventQueue.async { [weak self] in self?.handler.windowClosed(pid) }
        }
    }

    public func move(_ id: WindowID, toSpace space: SpaceID) async -> Result<Void, WindowError> {
        guard capabilities.contains(.moveAcrossSpaces) else { return await spaceMoves.move(id, to: space) }
        guard await prepare() else { return .failure(.notAuthorized) }
        return await spaceMoves.move(id, to: space)
    }

    public func addSpace(on display: DisplayID, switching: Bool) async -> Result<SpaceInfo, WindowError> {
        start()
        let mark = desktopWatch.changes
        let result = await missionControl.add(on: display, switching: switching)
        guard case .success(let added) = result else { return result }
        announceDesktops(changedSince: mark)
        return .success(await Self.confirmingCurrent(added, switching: switching) { await self.spaces() })
    }

    /// What `addSpace` answers for the desktop the flow made. One it asked to go to and could not
    /// confirm as current is looked up once more: a switch can land after the wait for it ran
    /// out, and the answer has to agree with the Space list.
    static func confirmingCurrent(_ added: SpaceInfo, switching: Bool,
                                  spaces: () async -> [SpaceInfo]) async -> SpaceInfo {
        guard switching, !added.isCurrent, let listed = await spaces().first(where: { $0.id == added.id }) else {
            return added
        }
        var added = added
        added.isCurrent = listed.isCurrent
        return added
    }

    public func switchTo(space: SpaceID, focusing preferred: WindowID?) async -> Result<Void, WindowError> {
        // Only the Space list says which desktop shows: without it nothing can be confirmed.
        guard capabilities.contains(.spaceList) else {
            return .failure(.unsupported(unavailableReason(for: .spaceList) ?? L10n.text("windowkit.cannot.read.the.desktop.list")))
        }
        // Not primed here: the flow's `windows()` runs the one full scan it needs.
        guard await prepare(prime: false) else { return .failure(.notAuthorized) }
        return await desktopSwitcher.switchTo(space, focusing: preferred)
    }

    public func removeSpace(_ space: SpaceID) async -> Result<Void, WindowError> {
        await removeSpace(space, onlyIfEmpty: false)
    }

    public func removeSpaceIfEmpty(_ space: SpaceID) async -> Result<Void, WindowError> {
        await removeSpace(space, onlyIfEmpty: true)
    }

    private func removeSpace(_ space: SpaceID, onlyIfEmpty: Bool) async -> Result<Void, WindowError> {
        start()
        let mark = desktopWatch.changes
        let removal = await missionControl.removal(of: space, onlyIfEmpty: onlyIfEmpty)
        // The desktop's windows are on a neighbouring one now, and callers read their `spaceIDs`
        // next. After a failure too: a removal that was sent can land after the wait for it ran
        // out. Not when the flow ended before it asked for Mission Control: nothing was sent.
        if removal.opened { await scans.scan(.all) }
        if case .success = removal.result { announceDesktops(changedSince: mark) }
        return removal.result
    }

    public func canOpenNewWindow(pid: Int32) async -> Bool? {
        // Without permission the menus cannot be read, which says nothing about them.
        guard await prepare(prime: false) else { return nil }
        return await newWindows.canOpen(pid: pid)
    }

    public func openNewWindow(pid: Int32) async -> Result<WindowID, WindowError> {
        // Primed, so that the window list the new window joins is whole and the only `.appeared`
        // is the new window's.
        guard await prepare() else { return .failure(.notAuthorized) }
        return await newWindows.open(pid: pid)
    }

    public func hideApplication(pid: Int32) async -> Result<Void, WindowError> {
        start()
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
            return .failure(.rejected(L10n.text("windowkit.the.app.could.not.be.found.it")))
        }
        let name = app.localizedName ?? L10n.text("windowkit.application")
        if await MainActor.run(body: { app.hide() }) { return .success(()) }
        guard isAuthorized else { return .failure(.notAuthorized) }
        let actions = self.actions
        let failure = await run(on: actionQueue) { actions.hideThroughAccessibility(pid: pid) }
        return failure == nil ? .success(()) : .failure(.rejected(L10n.text("windowkit.refused.to.hide", String(describing: (name)))))
    }

    /// `succeeded` receives the window's pid.
    private func perform(on id: WindowID, _ action: @escaping (WindowActions, AXUIElement) -> AXFailure?,
                         succeeded: (Int32) -> Void = { _ in }) async -> Result<Void, WindowError> {
        guard await prepare() else { return .failure(.notAuthorized) }
        guard let entry = await entry(for: id) else { return .failure(.windowNotFound(id)) }
        let actions = self.actions
        guard let failure = await run(on: actionQueue, { action(actions, entry.handle.element) }) else {
            succeeded(entry.info.pid)
            return .success(())
        }
        return .failure(healing(failure.windowError(id: id, pid: entry.info.pid, appName: entry.info.appName),
                                pid: entry.info.pid))
    }

    /// A vanished element may only mean the app rebuilt it; rescanning the app lets the
    /// next request find the window again, or confirms that it is gone.
    private func healing(_ error: WindowError, pid: Int32) -> WindowError {
        if case .windowNotFound = error { scans.schedule(.applications([pid]), after: 0) }
        return error
    }

    private static func duration(of animation: FrameAnimation) -> Double {
        switch animation {
        case .none: return 0
        case .animated(let seconds): return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : seconds
        }
    }
}
