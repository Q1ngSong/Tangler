import Contracts
import CoreGraphics

/// Turns system notifications into registry changes and WindowEvents. Runs on one serial
/// queue; every system read goes through `source` or `hooks`, so tests can script them.
final class WindowEventHandler<Source: InventorySource> {
    struct Hooks {
        /// nil for applications the inventory does not manage.
        var application: (Int32) -> AppSnapshot?
        var frontmostPID: () -> Int32?
        var ownPID: Int32
        /// The application's focused window, read through Accessibility.
        var focusedWindow: (Int32) -> Source.Handle?
        /// The window server's entry for a window; nil once the window is gone.
        var record: (WindowID) -> WindowServerRecord?
        var displays: () -> [DisplayInfo]
        /// Reads the Space list; true when its desktops are not the ones last seen.
        var noticesDesktopChange: () -> Bool
        /// For events that are not window changes; those come from the registry.
        var emit: (WindowEvent) -> Void
        var scheduleScan: (ScanScope) -> Void
        /// A scan a while later, for changes no notification will report.
        var scheduleFollowUpScan: (ScanScope) -> Void
        /// Starts or stops per-window notifications.
        var observe: (Source.Handle, Int32) -> Void
        var forget: (Source.Handle, Int32) -> Void
    }

    private let source: Source
    private let registry: WindowRegistry<Source.Handle>
    private let hooks: Hooks

    init(source: Source, registry: WindowRegistry<Source.Handle>, hooks: Hooks) {
        self.source = source
        self.registry = registry
        self.hooks = hooks
    }

    func handle(_ notification: WindowNotification, element: Source.Handle, pid: Int32) {
        switch notification {
        case .created: learn(element, pid: pid)
        case .changed: reread(element, pid: pid)
        case .destroyed: destroyed(element, pid: pid)
        case .focusChanged:
            // Every app reports its own focus changes; only the frontmost one has system focus.
            // The notified element may be stale by now (see `NotificationDispatch`).
            guard pid == hooks.frontmostPID(), let focused = hooks.focusedWindow(pid) else { return }
            focus(focused, pid: pid)
        }
    }

    func applicationLaunched(_ pid: Int32) {
        hooks.emit(.appLaunched(pid: pid))
        hooks.scheduleScan(.applications([pid]))
        // Windows a slow starter opens before it answers Accessibility send no notification.
        hooks.scheduleFollowUpScan(.applications([pid]))
    }

    func applicationTerminated(_ pid: Int32) {
        // A quitting app's windows send no destroyed notifications of their own.
        registry.removeAll(pid: pid, stamp: source.nextStamp())
        hooks.emit(.appTerminated(pid: pid))
    }

    /// A window of `pid` accepted a close request. Apps that keep closed windows only order
    /// them out and send no notification, so scans look now and again after a close animation.
    func windowClosed(_ pid: Int32) {
        hooks.scheduleScan(.applications([pid]))
        hooks.scheduleFollowUpScan(.applications([pid]))
    }

    func applicationHidden(_ pid: Int32) { hooks.emit(.appHidden(pid: pid)) }
    func applicationUnhidden(_ pid: Int32) { hooks.emit(.appUnhidden(pid: pid)) }

    func applicationActivated(_ pid: Int32) {
        guard pid != hooks.ownPID, let element = hooks.focusedWindow(pid) else { return }
        focus(element, pid: pid)
    }

    func activeSpaceChanged() {
        // Removing the desktop one is on, or leaving a full-screen Space that ends, changes both.
        if hooks.noticesDesktopChange() { hooks.emit(.spacesChanged) }
        hooks.emit(.currentSpaceChanged)
        hooks.scheduleScan(.all)
    }

    func displaysChanged() {
        hooks.emit(.displaysChanged)
        hooks.scheduleScan(.all)
    }

    /// Reads a known window again, the Spaces it is on included, for a caller that asks what it
    /// is now. Notifications only bring `reread`, which leaves the Spaces alone: no notification
    /// says that a window changed desktops.
    func refresh(_ element: Source.Handle, pid: Int32) {
        reread(element, pid: pid)
        guard let id = registry.id(for: element), let spaceIDs = source.spaceIDs(of: id) else { return }
        registry.update(id, fields: .spaces, stamp: source.nextStamp()) { $0.spaceIDs = spaceIDs }
    }

    /// The window with keyboard focus. While Tangler itself is frontmost, e.g. with a panel
    /// open, the last window focused before it still counts. nil when a scan must run first.
    func focusedWindowID() -> WindowID? {
        guard let pid = hooks.frontmostPID(), pid != hooks.ownPID else { return registry.focusedID }
        guard let element = hooks.focusedWindow(pid) else { return nil }
        focus(element, pid: pid)
        return registry.id(for: element)
    }

    // MARK: Notifications

    private func learn(_ element: Source.Handle, pid: Int32) {
        guard let app = hooks.application(pid) else { return }
        // A new window may not answer yet, may start tiny or off the normal layer, may be missing
        // from the window server list, or, without the exact lookup, need a scan to be paired with
        // its window server entry. Scans look again now and a while later, so none is missed.
        guard let snapshot = source.reread(element), let id = snapshot.exactID, let frame = snapshot.frame,
              AXWindowSnapshot<Source.Handle>.hasManageableSize(frame),
              hooks.record(id).map(\.hasManageableShape) ?? snapshot.isMinimized else {
            hooks.scheduleScan(.applications([pid]))
            hooks.scheduleFollowUpScan(.applications([pid]))
            return
        }
        let info = snapshot.info(id: id, frame: frame, app: app, displays: hooks.displays(),
                                 spaceIDs: source.spaceIDs(of: id) ?? [])
        registry.upsert(ScannedWindow(info: info, handle: element, stamp: snapshot.stamp))
        hooks.observe(element, pid)
    }

    private func reread(_ element: Source.Handle, pid: Int32) {
        guard let id = registry.id(for: element), let entry = registry.entry(id) else { return }
        guard let snapshot = source.reread(element) else {
            // A busy app may only have timed out, so only a window known to be gone is removed.
            if hooks.record(id) == nil || isOpenWithoutElement(id, pid: pid) == false {
                remove(id, element: element, pid: pid)
            }
            return
        }
        guard let frame = snapshot.frame else { return }
        let app = AppSnapshot(pid: entry.info.pid, bundleID: entry.info.bundleID, name: entry.info.appName)
        let info = snapshot.info(id: id, frame: frame, app: app, displays: hooks.displays(), spaceIDs: entry.info.spaceIDs)
        // Spaces are not read here, so they keep whatever the registry learned meanwhile.
        registry.upsert(ScannedWindow(info: info, handle: element, stamp: snapshot.stamp, fields: [.frame, .details]))
    }

    private func destroyed(_ element: Source.Handle, pid: Int32) {
        guard let id = registry.id(for: element) else { return }
        if hooks.record(id) == nil || isOpenWithoutElement(id, pid: pid) == false {
            remove(id, element: element, pid: pid)
        } else {
            // The window may live on, e.g. its element was replaced, or it is still closing:
            // scans find its new element or confirm that it is gone.
            hooks.forget(element, pid)
            hooks.scheduleScan(.applications([pid]))
            hooks.scheduleFollowUpScan(.applications([pid]))
        }
    }

    /// `UnlistedWindows` for a window the window server still has; nil when only a scan can tell.
    private func isOpenWithoutElement(_ id: WindowID, pid: Int32) -> Bool? {
        UnlistedWindows.isOpen(appIsHidden: hooks.application(pid)?.isHidden ?? false, spaceIDs: source.spaceIDs(of: id))
    }

    private func focus(_ element: Source.Handle, pid: Int32) {
        if registry.id(for: element) == nil { learn(element, pid: pid) }
        if let id = registry.id(for: element) { registry.setFocused(id) }
    }

    private func remove(_ id: WindowID, element: Source.Handle, pid: Int32) {
        hooks.forget(element, pid)
        registry.remove(id, stamp: source.nextStamp())
    }
}
