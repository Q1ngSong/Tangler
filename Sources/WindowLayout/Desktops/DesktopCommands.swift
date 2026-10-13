import CoreKit
import Contracts

/// What a declared desktop command does.
enum DesktopCommand: Equatable, Sendable {
    case new
    case remove
    case cleanEmpty
    /// `.number` takes the digit from `CommandContext.argument` when it runs.
    case switchTo(DesktopChoice)

    /// Every command in `DesktopCommands.all`; a test checks that the two lists agree.
    static let byID: [CommandID: DesktopCommand] = [
        "layout.desktopNew": .new,
        "layout.desktopRemove": .remove,
        "layout.desktopCleanEmpty": .cleanEmpty,
        "layout.desktopSwitch": .switchTo(.number(nil)),
        "layout.desktopPrevious": .switchTo(.previous),
        "layout.desktopNext": .switchTo(.next),
    ]
}

/// Commands that add, remove and show desktops. They share the layout module's D group, so
/// they belong to the layout module.
enum DesktopCommands {
    static let all: [CommandSpec] = [
        spec("desktopNew", "windowlayout.create.and.switch.to.a.desktop", KeySequence("d", "n")),
        spec("desktopRemove", "windowlayout.remove.current.desktop", KeySequence("d", "x")),
        CommandSpec(id: "layout.desktopCleanEmpty", module: LayoutCommands.module, titleKey: "windowlayout.clean.up.all.empty.desktops",
                    aliases: ["空白桌面", "清理桌面", "clean empty desktops"],
                    leaderKeys: [KeySequence("d", "c")], entryPoints: [.leader, .palette]),
        spec("desktopSwitch", "windowlayout.switch.to.desktop.n", KeySequence(.key("d"), .anyDigit)),
        spec("desktopPrevious", "windowlayout.switch.to.desktop.on.the.left", KeySequence("d", "[")),
        spec("desktopNext", "windowlayout.switch.to.desktop.on.the.right", KeySequence("d", "]")),
    ]

    private static func spec(_ action: String, _ title: String, _ keys: KeySequence) -> CommandSpec {
        CommandSpec(id: CommandID(rawValue: "layout.\(action)"), module: LayoutCommands.module, titleKey: title,
                    leaderKeys: [keys], entryPoints: [.leader, .palette])
    }
}
