import CoreKit
import Contracts

/// Tab group commands and their default leader keys (tab groups design 5).
enum TabCommands {
    static let module: ModuleID = "tabs"

    static let groups: [LeaderGroup] = [
        LeaderGroup(prefix: KeySequence("t"), module: module, titleKey: "tabgroups.tab.groups"),
    ]

    static let all: [CommandSpec] = [
        spec("mergeArea", "tabgroups.group.windows.in.the.same.area", KeySequence("t", "t"), [.leader, .palette, .menuBar],
             aliases: ["标签组", "tabs"]),
        spec("addWindow", "tabgroups.pick.a.window.to.add.to.a", KeySequence("t", "a"), [.leader, .palette]),
        spec("next", "tabgroups.next.tab", KeySequence("]"), [.leader, .palette], lingers: true),
        spec("previous", "tabgroups.previous.tab", KeySequence("["), [.leader, .palette], lingers: true),
        spec("select", "tabgroups.select.tab.n", KeySequence(.key("t"), .anyDigit), [.leader, .palette]),
        spec("remove", "tabgroups.remove.from.tab.group", KeySequence("t", "x"), [.leader, .palette, .menuBar]),
        spec("ungroup", "tabgroups.ungroup.windows", KeySequence("t", "u"), [.leader, .palette]),
    ]

    private static func spec(_ action: String, _ title: String, _ keys: KeySequence, _ entryPoints: Set<EntryPoint>,
                             aliases: [String] = [], lingers: Bool = false) -> CommandSpec {
        CommandSpec(id: CommandID(rawValue: "tabs.\(action)"), module: module, titleKey: title, aliases: aliases,
                    leaderKeys: [keys], entryPoints: entryPoints, target: .focusedWindow, lingersAfterRun: lingers)
    }
}

/// What a declared command does.
enum TabCommand: Equatable, Sendable {
    case mergeArea, addWindow, next, previous, select, remove, ungroup

    /// Every command in `TabCommands.all`; a test checks that the two lists agree.
    static let byID: [CommandID: TabCommand] = [
        "tabs.mergeArea": .mergeArea, "tabs.addWindow": .addWindow, "tabs.next": .next,
        "tabs.previous": .previous, "tabs.select": .select, "tabs.remove": .remove, "tabs.ungroup": .ungroup,
    ]
}
