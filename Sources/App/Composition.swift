import CaptureKit
import CommandKit
import Contracts
import InputKit
import SettingsKit
import WindowKit

/// The real services and the running modules: the only place that knows concrete types
/// (design section 2.2, rule 3).
@MainActor
final class Composition {
    let windows = SystemWindowService()
    let input = SystemInputService()
    let capture = SystemCaptureService()
    let settings = UserDefaultsSettingsStore()
    let commands: LiveCommandRegistry
    let runner = ModuleRunner()

    init() {
        commands = LiveCommandRegistry(input: input, settings: settings)
    }

    private var modulesStarted = false

    /// Starts the services, and the modules once Accessibility is granted: without it the
    /// switcher would turn the system Command-Tab off while Tangler's own cannot work.
    func start() async {
        startServices()
        if windows.isAuthorized { await startModules() }
    }

    func startModules() async {
        guard !modulesStarted else { return }
        modulesStarted = true
        let appSettings = settings.load(AppSettings.self)
        await runner.start(FeatureCatalog.all, isEnabled: appSettings.isEnabled) { [self] shared in
            ModuleContext(windows: windows, input: input, capture: capture, commands: commands,
                          settings: settings, placement: shared.placement, tabGroups: shared.tabGroups,
                          desktopOwnership: shared.desktopOwnership)
        }
    }

    /// Without Accessibility the event tap and the observers cannot start; call again once
    /// the permission arrives.
    func startServices() {
        windows.start()
        // Creating the event tap before Accessibility is granted only makes macOS show one
        // more prompt, so the tap waits for the permission.
        if windows.isAuthorized { _ = input.start() }
    }

    func stop() async {
        await runner.stop()
        input.stop()
        windows.stop()
    }

    /// Runs a command from the menu bar against the window focused before the menu opened.
    func perform(_ id: CommandID) async -> CommandResult {
        let target = await windows.focusedWindowID()
        return await commands.perform(id, context: CommandContext(targetWindow: target))
    }
}
