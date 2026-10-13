import CoreKit
import AppKit
import Contracts
import SwiftUI

/// Manual layout: edge snapping, the Option grid, layout commands and the placement service
/// (design sections 4.1 and 4.2). Every operation changes only the window it acts on, and
/// nothing happens when windows open or close.
@MainActor
public final class WindowLayoutModule: FeatureModule {
    public static let moduleID = LayoutCommands.module
    public static var displayName: String { L10n.text("windowlayout.layout") }
    public static var declaredCommands: [CommandSpec] { LayoutCommands.all + DesktopCommands.all }
    public static var declaredLeaderGroups: [LeaderGroup] { LayoutCommands.groups }
    public static var settingsType: (any ModuleSettings.Type)? { LayoutSettings.self }

    private let context: ModuleContext
    private let mover: WindowMover
    private let runner: LayoutCommandRunner
    private let desktops: DesktopController
    private let desktopKeys: DesktopKeys
    private var isRunning = false
    private let drag: DragController
    private let placement: LayoutPlacementService
    private let readTiling: () -> SystemTiling
    private var settingsTask: Task<Void, Never>?
    private(set) var currentSettings = LayoutSettings.defaultValue

    public convenience init(context: ModuleContext) {
        self.init(context: context, presenter: OverlaySnapPreviewPresenter(), readTiling: SystemTiling.current)
    }

    init(context: ModuleContext, presenter: any SnapPreviewPresenter, readTiling: @escaping () -> SystemTiling,
         buttonCheckTicks: @escaping () -> AsyncStream<Void>
             = DragController.ticks(every: DragController.buttonCheckInterval)) {
        self.context = context
        self.readTiling = readTiling
        mover = WindowMover(windows: context.windows)
        runner = LayoutCommandRunner(windows: context.windows, mover: mover)
        let desktops = DesktopController(windows: context.windows, owner: { context.desktopOwnership })
        self.desktops = desktops
        desktopKeys = DesktopKeys(input: context.input) { await desktops.run($0, context: $1) }
        placement = LayoutPlacementService(windows: context.windows, mover: mover)
        drag = DragController(windows: context.windows, input: context.input, mover: mover, presenter: presenter,
                              settings: currentSettings, buttonCheckTicks: buttonCheckTicks)
    }

    /// Events the drag controller has handled, for tests that drive it through the services.
    var processedDragEvents: Int { drag.processedEvents }

    /// Whether the system's desktop shortcuts are taken over right now.
    var handlesDesktopKeys: Bool { desktopKeys.isEnabled }

    public func start() async throws {
        apply(context.settings.load(LayoutSettings.self))
        do {
            for group in Self.declaredLeaderGroups {
                try context.commands.registerGroup(group)
            }
            for spec in LayoutCommands.all {
                let command = LayoutCommand.byID[spec.id]
                try context.commands.register(spec) { [weak self] commandContext in
                    guard let self, let command else { return .unavailable(reason: L10n.text("windowlayout.the.layout.module.is.not.running")) }
                    return await self.runner.run(command, context: commandContext)
                }
            }
            for spec in DesktopCommands.all {
                let command = DesktopCommand.byID[spec.id]
                try context.commands.register(spec) { [weak self] commandContext in
                    guard let self, let command else { return .unavailable(reason: L10n.text("windowlayout.the.layout.module.is.not.running")) }
                    return await self.desktops.run(command, context: commandContext)
                }
            }
        } catch {
            context.commands.unregisterAll(module: Self.moduleID)
            throw error
        }
        drag.start()
        isRunning = true
        desktopKeys.setEnabled(currentSettings.handlesDesktopKeys)
        let changes = context.settings.changes(LayoutSettings.self)
        settingsTask = Task { [weak self] in
            for await settings in changes { self?.apply(settings) }
        }
    }

    public func stop() async {
        settingsTask?.cancel()
        settingsTask = nil
        isRunning = false
        desktopKeys.setEnabled(false)
        drag.stop()
        context.commands.unregisterAll(module: Self.moduleID)
    }

    public func providedServices() -> [ProvidedService] {
        [.placement(placement)]
    }

    /// The macOS tiling options that fight the layout settings in use, one line each, so the
    /// App can point them out at first launch (design section 4.1); the settings page lists
    /// the same lines. Nothing is changed.
    public func systemTilingConflicts() -> [String] {
        readTiling().conflicts(with: context.settings.load(LayoutSettings.self))
    }

    public func makeSettingsView() -> AnyView? {
        let model = LayoutSettingsModel(store: context.settings, readTiling: readTiling,
                                        openURL: { NSWorkspace.shared.open($0) })
        return AnyView(LayoutSettingsView(model: model))
    }

    private func apply(_ settings: LayoutSettings) {
        currentSettings = settings
        runner.settings = settings
        mover.animation = settings.animation
        drag.update(settings: settings)
        // Only while the module runs: a stopped module holds no shortcut.
        desktopKeys.setEnabled(isRunning && settings.handlesDesktopKeys)
    }
}
