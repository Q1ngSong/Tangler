import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: SettingsModel
    private var refreshTimer: Timer?
    /// Built on first show, and built again in place when the skin changes: the skins differ in
    /// the window's style, which is never changed on an open window (Liquid Glass skin design 3.2).
    private var window: NSWindow?

    init(composition: Composition, updates: AppUpdates? = nil) {
        model = SettingsModel(composition: composition, updates: updates)
        super.init()
        model.onSkinChange = { [weak self] _ in
            // On the next turn, so the appearance card finishes handling this click first.
            Task { @MainActor in self?.rebuildWindow() }
        }
    }

    func show(page: SettingsPage? = nil) {
        if let page { model.page = page }
        model.refresh()
        NSApp.activate()
        let window = self.window ?? makeCenteredWindow()
        window.makeKeyAndOrderFront(nil)
        // Permissions change in System Settings while this window stays open; re-read them
        // so the page never shows a stale state.
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.refresh(loginItem: false) }
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        model.refresh()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        Self.constrainedFrameSize(frameSize, for: sender)
    }

    func windowWillClose(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func makeCenteredWindow() -> NSWindow {
        let window = makeWindow()
        window.center()
        return window
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.contentSize), styleMask: Self.classicStyle,
                              backing: .buffered, defer: true)
        Self.configure(window, content: Self.hosting(SettingsView(model: model)), skin: model.appSettings.skin)
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        return window
    }

    /// Hosts settings content without letting it size the window. The window keeps the size it
    /// was given or the user chose; a page that needs more room scrolls. With the default
    /// sizing, the window grew to a page's minimum height, over 1400 points for 工作空间.
    static func hosting<Content: View>(_ content: Content) -> NSHostingController<Content> {
        let controller = NSHostingController(rootView: content)
        controller.sizingOptions = []
        return controller
    }

    /// Replaces the window with one in the new skin at the same frame. The old one goes without
    /// a close notification, so the refresh timer keeps running against the same model, and the
    /// page stays where it was.
    private func rebuildWindow() {
        guard let old = window else { return }
        let frame = old.frame
        let wasVisible = old.isVisible
        old.delegate = nil
        old.orderOut(nil)
        let window = makeWindow()
        window.setFrame(NSRect(origin: frame.origin, size: Self.constrainedFrameSize(frame.size, for: window)), display: false)
        if wasVisible { window.makeKeyAndOrderFront(nil) }
    }
}
