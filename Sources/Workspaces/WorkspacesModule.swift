import CoreKit
import Contracts
import SwiftUI

/// Named checkpoints, each opened on a desktop of its own (workspaces design).
@MainActor
public final class WorkspacesModule: FeatureModule {
    public static let moduleID = WorkspaceCommands.module
    public static var displayName: String { L10n.text("workspaces.workspaces") }
    public static var declaredCommands: [CommandSpec] { WorkspaceCommands.all }
    public static var declaredLeaderGroups: [LeaderGroup] { WorkspaceCommands.groups }
    public static var settingsType: (any ModuleSettings.Type)? { WorkspaceSettings.self }
    public static let requiredServices: Set<ServiceKind> = [.placement]

    let controller: WorkspacesController
    let settingsNavigation = WorkspaceSettingsNavigation()
    private let context: ModuleContext

    public convenience init(context: ModuleContext) {
        self.init(context: context, environment: .system())
    }

    init(context: ModuleContext, environment: WorkspaceEnvironment) {
        self.context = context
        controller = WorkspacesController(context: context, environment: environment)
    }

    public func start() async throws {
        controller.start()
        for group in Self.declaredLeaderGroups {
            try context.commands.registerGroup(group)
        }
        let handlers: [CommandID: CommandHandler] = [
            "workspace.save": { [weak self] _ in
                guard let controller = self?.controller else { return Self.stopped }
                return controller.announce(await controller.saveCurrentDesktop().result)
            },
            "workspace.open": { [weak self] context in
                guard let controller = self?.controller else { return Self.stopped }
                return controller.announce(controller.open(digit: context.argument))
            },
            "workspace.revert": { [weak self] _ in
                guard let controller = self?.controller else { return Self.stopped }
                return controller.announce(await controller.revertCurrentDesktop())
            },
            "workspace.release": { [weak self] _ in
                guard let controller = self?.controller else { return Self.stopped }
                return controller.announce(await controller.releaseCurrentDesktop())
            },
        ]
        for spec in Self.declaredCommands {
            guard let handler = handlers[spec.id] else { continue }
            try context.commands.register(spec, handler: handler)
        }
        context.commands.addDynamicSource(WorkspaceCommandSource(controller: controller))
    }

    public func stop() async {
        // Tangler quitting stops the module too: the open workspaces are saved first.
        await controller.saveBeforeStopping()
        controller.stop()
        context.commands.removeDynamicSources(module: Self.moduleID)
        context.commands.unregisterAll(module: Self.moduleID)
    }

    public func providedServices() -> [ProvidedService] {
        [.desktopOwnership(controller)]
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(WorkspaceSettingsView(controller: controller, navigation: settingsNavigation))
    }

    private static let stopped = CommandResult.unavailable(reason: WorkspacesController.stopped)
}
