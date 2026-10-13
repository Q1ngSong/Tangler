import CoreKit
import Contracts
import SwiftUI

/// Window previews when hovering Dock icons, and Dock click behaviour (design section 4.4).
/// Offers no commands.
@MainActor
public final class DockPreviewModule: FeatureModule {
    public static let moduleID: ModuleID = "dock"
    public static var displayName: String { L10n.text("dockpreview.dock.preview") }
    public static let declaredCommands: [CommandSpec] = []
    public static var settingsType: (any ModuleSettings.Type)? { DockPreviewSettings.self }

    let controller: DockPreviewController
    private let context: ModuleContext
    private var settingsTask: Task<Void, Never>?

    public convenience init(context: ModuleContext) {
        self.init(context: context, scheduler: SystemDockScheduler(), presenter: DockPreviewPanel())
    }

    init(context: ModuleContext, scheduler: any DockScheduler, presenter: any DockPreviewPresenting) {
        self.context = context
        controller = DockPreviewController(windows: context.windows, input: context.input, capture: context.capture,
                                           scheduler: scheduler, presenter: presenter)
    }

    public func start() async throws {
        settingsTask?.cancel()
        // Subscribe before loading so a save in between is not lost.
        let changes = context.settings.changes(DockPreviewSettings.self)
        controller.apply(context.settings.load(DockPreviewSettings.self))
        settingsTask = Task { [weak self] in
            for await settings in changes { self?.controller.apply(settings) }
        }
    }

    public func stop() async {
        settingsTask?.cancel()
        settingsTask = nil
        controller.stop()
        context.commands.unregisterAll(module: Self.moduleID)
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(DockPreviewSettingsView(store: context.settings, windows: context.windows))
    }
}
