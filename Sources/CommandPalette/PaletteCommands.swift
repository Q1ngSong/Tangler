import CoreKit
import Contracts

enum PaletteCommands {
    static let module: ModuleID = "palette"

    static let open = CommandSpec(id: "palette.open", module: module, titleKey: "commandpalette.open.command.search",
                                  leaderKeys: [KeySequence(.space)], entryPoints: [.leader, .menuBar])

    static let all: [CommandSpec] = [open]
}
