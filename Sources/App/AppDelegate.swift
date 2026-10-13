import AppKit
import OverlayKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let composition = Composition()
    private var updates: AppUpdates?
    private var shutdownTask: Task<Void, Never>?
    private var statusMenu: StatusMenu?
    private var settingsWindow: SettingsWindowController?
    private var permissionTimer: Timer?
    private var terminationSignal: DispatchSourceSignal?
    private var stopping = false
    private var stopped = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        quitNormallyOnSIGTERM()
        // Before anything is drawn, so the first overlay already has the user's skin.
        CurrentSkin.shared.value = composition.settings.load(AppSettings.self).skin
        let updates = AppUpdates { [weak self] in await self?.stopComposition() }
        self.updates = updates
        updates.start()
        let settingsWindow = SettingsWindowController(composition: composition, updates: updates)
        self.settingsWindow = settingsWindow
        statusMenu = StatusMenu(composition: composition, updates: updates, openSettings: { settingsWindow.show() })
        Task {
            await composition.start()
            if !composition.windows.isAuthorized {
                settingsWindow.show(page: .diagnostics)
                waitForAccessibility()
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if stopped { return .terminateNow }
        // Stopping is asynchronous, so cancel this quit and quit again once it is done.
        // `.terminateLater` would wait in a nested run loop, which deadlocks when the quit
        // comes from a main-queue block such as the SIGTERM handler.
        if !stopping {
            stopping = true
            Task {
                await stopComposition()
                sender.terminate(nil)
            }
        }
        return .terminateCancel
    }

    /// Quit and updater relaunch share one shutdown, including workspace checkpoint saving.
    private func stopComposition() async {
        stopping = true
        permissionTimer?.invalidate()
        permissionTimer = nil
        if shutdownTask == nil { shutdownTask = Task { await composition.stop() } }
        await shutdownTask?.value
        stopped = true
    }

    /// `killall Tangler` (SIGTERM) quits like the menu does, so modules stop and the system
    /// Command-Tab switcher comes back; scripts/install-app.sh relies on this.
    private func quitNormallyOnSIGTERM() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { NSApp.terminate(nil) }
        }
        source.resume()
        terminationSignal = source
    }

    /// The user grants Accessibility while Tangler runs; start the services then. Checked
    /// every 2 seconds, which is as often as InputKit's permission probe should run.
    private func waitForAccessibility() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, self.composition.windows.isAuthorized else { return }
                timer.invalidate()
                self.composition.startServices()
                Task { await self.composition.startModules() }
            }
        }
    }
}
