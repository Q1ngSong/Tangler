import CoreKit
import Contracts
import OverlayKit
import SwiftUI

/// Tab groups (tab groups design): windows sharing one area behind a Chrome-like tab bar, where a
/// click on a tab brings only that window forward.
@MainActor
public final class TabGroupsModule: FeatureModule {
    public static let moduleID = TabCommands.module
    public static var displayName: String { L10n.text("tabgroups.tab.groups") }
    public static var declaredCommands: [CommandSpec] { TabCommands.all }
    public static var declaredLeaderGroups: [LeaderGroup] { TabCommands.groups }
    public static var settingsType: (any ModuleSettings.Type)? { TabGroupsSettings.self }

    let controller: TabsController
    private let provider: TabGroupProvider
    private let context: ModuleContext
    private var settingsTask: Task<Void, Never>?

    public convenience init(context: ModuleContext) {
        let picker = WindowPicker(windows: context.windows)
        self.init(context: context, presenter: TabBarPanels(), scheduler: SystemTabScheduler(),
                  pick: { await picker.pick(prompt: L10n.text("tabgroups.click.a.window.to.add.to.the")) })
    }

    init(context: ModuleContext, presenter: any TabBarPresenting, scheduler: any TabScheduler,
         pick: @escaping @MainActor () async -> WindowInfo?) {
        self.context = context
        controller = TabsController(windows: context.windows, input: context.input, placement: context.placement,
                                    presenter: presenter, scheduler: scheduler, pick: pick)
        provider = TabGroupProvider(controller: controller)
    }

    public func start() async throws {
        settingsTask?.cancel()
        // Subscribe before loading so a save in between is not lost.
        let changes = context.settings.changes(TabGroupsSettings.self)
        controller.apply(context.settings.load(TabGroupsSettings.self))
        do {
            for group in Self.declaredLeaderGroups { try context.commands.registerGroup(group) }
            for spec in Self.declaredCommands {
                let command = TabCommand.byID[spec.id]
                try context.commands.register(spec) { [weak self] commandContext in
                    guard let self, let command else { return .unavailable(reason: L10n.text("tabgroups.the.tab.group.module.is.not.running")) }
                    return await self.controller.perform(command, context: commandContext)
                }
            }
        } catch {
            context.commands.unregisterAll(module: Self.moduleID)
            throw error
        }
        controller.start()
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

    public func providedServices() -> [ProvidedService] {
        [.tabGroups(provider)]
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(TabGroupsSettingsView(store: context.settings,
                                      commands: context.commands.commands.filter { $0.module == Self.moduleID }))
    }
}
