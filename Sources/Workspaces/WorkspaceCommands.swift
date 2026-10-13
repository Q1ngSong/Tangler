import CoreKit
import Contracts

enum WorkspaceCommands {
    static let module: ModuleID = "workspace"

    static let groups: [LeaderGroup] = [
        LeaderGroup(prefix: KeySequence("w"), module: module, titleKey: "workspaces.workspaces"),
    ]

    static let all: [CommandSpec] = [
        CommandSpec(id: "workspace.open", module: module, titleKey: "workspaces.open.workspace.n",
                    leaderKeys: [KeySequence(.key("w"), .anyDigit)], entryPoints: [.leader, .palette]),
        CommandSpec(id: "workspace.save", module: module, titleKey: "workspaces.save.checkpoint",
                    leaderKeys: [KeySequence("w", "s")], entryPoints: [.leader, .palette, .menuBar]),
        CommandSpec(id: "workspace.revert", module: module, titleKey: "workspaces.restore.checkpoint",
                    leaderKeys: [KeySequence("w", "r")], entryPoints: [.leader, .palette]),
        CommandSpec(id: "workspace.release", module: module, titleKey: "workspaces.release.current.workspace",
                    leaderKeys: [KeySequence("w", "x")], entryPoints: [.leader, .palette]),
    ]
}
