import CoreKit
import Contracts
import Foundation

/// One command per workspace, which opens it: by its name in the palette, and as an item of the
/// status bar menu that is ticked while the workspace is open.
@MainActor
final class WorkspaceCommandSource: DynamicCommandSource {
    let moduleID = WorkspaceCommands.module
    private let controller: WorkspacesController

    init(controller: WorkspacesController) {
        self.controller = controller
    }

    func dynamicCommands() async -> [DynamicCommand] {
        controller.library.workspaces.map { workspace in
            DynamicCommand(id: Self.prefix + workspace.id.uuidString, module: moduleID,
                           titleKey: "workspace.open.named", titleArguments: [workspace.name],
                           aliases: [workspace.name, Localizer(language: .english).format("workspace.open.named", [workspace.name]),
                                     Localizer(language: .simplifiedChinese).format("workspace.open.named", [workspace.name])],
                           menu: DynamicCommand.MenuItem(title: workspace.name,
                                                         isChecked: controller.state(of: workspace.id) != .closed))
        }
    }

    func perform(_ command: DynamicCommand) async -> CommandResult {
        guard command.id.hasPrefix(Self.prefix), let id = UUID(uuidString: String(command.id.dropFirst(Self.prefix.count))),
              let workspace = controller.library.workspace(id: id) else {
            return controller.announce(.unavailable(reason: L10n.text("commandkit.no.longer.exists", String(describing: (command.title)))))
        }
        return controller.announce(controller.open(workspace))
    }

    private static let prefix = "workspace.open:"
}
