import CoreKit
import Contracts
import SwiftUI

/// Command-Tab window switcher with horizontal thumbnails (design section 4.3).
@MainActor
public final class SwitcherModule: FeatureModule {
    public static let moduleID = SwitcherCommands.module
    public static var displayName: String { L10n.text("switcher.switcher") }
    public static var declaredCommands: [CommandSpec] { SwitcherCommands.all }
    public static var settingsType: (any ModuleSettings.Type)? { SwitcherSettings.self }

    private let context: ModuleContext
    let controller: SwitcherController
    private var settingsTask: Task<Void, Never>?
    /// Whether the system's ⌘Tab switcher is turned off; nil while the module is stopped.
    private(set) var systemSwitcherSuppressed: Bool?

    public convenience init(context: ModuleContext) {
        self.init(context: context, environment: .system())
    }

    init(context: ModuleContext, environment: SwitcherEnvironment) {
        self.context = context
        controller = SwitcherController(windows: context.windows, input: context.input, capture: context.capture,
                                        environment: environment)
    }

    public func start() async throws {
        for spec in Self.declaredCommands {
            let id = spec.id
            try context.commands.register(spec) { [weak self] _ in
                await self?.open(id) ?? .unavailable(reason: SwitcherText.stopped)
            }
        }
        // Subscribe before loading so a save in between is not lost.
        let changes = context.settings.changes(SwitcherSettings.self)
        controller.settings = context.settings.load(SwitcherSettings.self)
        settingsTask = Task { [weak self] in
            for await settings in changes { self?.controller.settings = settings }
        }
        systemSwitcherSuppressed = context.input.setSystemSwitcherSuppressed(true)
        controller.start()
    }

    public func stop() async {
        controller.stop()
        settingsTask?.cancel()
        settingsTask = nil
        context.commands.unregisterAll(module: Self.moduleID)
        context.input.setSystemSwitcherSuppressed(false)
        systemSwitcherSuppressed = nil
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(SwitcherSettingsView(store: context.settings, notes: settingsNotes))
    }

    /// What the settings page warns about or explains.
    var settingsNotes: [String] {
        var notes: [String] = []
        if systemSwitcherSuppressed == false { notes.append(SwitcherText.systemSwitcherMayAppear) }
        if !context.capture.isAuthorized { notes.append(SwitcherText.noScreenRecording) }
        if !context.windows.capabilities.contains(.otherSpaceWindows) {
            notes.append(SwitcherText.currentSpaceOnly(reason: context.windows.unavailableReason(for: .otherSpaceWindows)))
        }
        return notes
    }

    private func open(_ id: CommandID) async -> CommandResult {
        guard let opening = SwitcherCommands.opening(id) else { return .unavailable(reason: SwitcherText.stopped) }
        // Read now, so the user's current shortcut decides which modifiers keep the switcher open.
        let chord = context.commands.commands.first { $0.id == id }?.globalShortcut
        return await controller.open(SwitcherRequest(kind: opening.kind, reverse: opening.reverse, chord: chord))
    }
}
