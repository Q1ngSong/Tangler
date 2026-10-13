import CoreKit
import Contracts

/// Layout commands and their default leader keys (design section 4.2).
enum LayoutCommands {
    static let module: ModuleID = "layout"

    static let groups: [LeaderGroup] = [
        LeaderGroup(prefix: KeySequence("d"), module: module, titleKey: "windowlayout.displays.and.desktops"),
        LeaderGroup(prefix: KeySequence("s"), module: module, titleKey: "windowkit.move.to.another.desktop"),
    ]

    static let all: [CommandSpec] = [
        resize("leftHalf", "overlaykit.left.half", KeySequence(.left)),
        resize("rightHalf", "windowlayout.right.half", KeySequence(.right)),
        resize("topHalf", "windowlayout.top.half", KeySequence(.up)),
        resize("bottomHalf", "windowlayout.bottom.half", KeySequence(.down)),
        resize("topLeft", "windowlayout.top.left.quarter", KeySequence("u")),
        resize("topRight", "windowlayout.top.right.quarter", KeySequence("i")),
        resize("bottomLeft", "windowlayout.bottom.left.quarter", KeySequence("j")),
        resize("bottomRight", "windowlayout.bottom.right.quarter", KeySequence("k")),
        resize("maximize", "windowlayout.maximize", KeySequence("f")),
        resize("center", "windowlayout.center", KeySequence("c")),
        resize("restore", "windowlayout.restore.previous.position", KeySequence("z")),
        move("displayLeft", "windowlayout.move.to.left.display", KeySequence("d", .left)),
        move("displayRight", "windowlayout.move.to.right.display", KeySequence("d", .right)),
        move("displayUp", "windowlayout.move.to.display.above", KeySequence("d", .up)),
        move("displayDown", "windowlayout.move.to.display.below", KeySequence("d", .down)),
        move("spaceLeft", "windowlayout.move.to.desktop.on.the.left", KeySequence("s", .left)),
        move("spaceRight", "windowlayout.move.to.desktop.on.the.right", KeySequence("s", .right)),
        move("spaceNumber", "windowlayout.move.to.desktop.n", KeySequence(.key("s"), .anyDigit)),
    ]

    /// Resizing commands also appear in the menu bar.
    private static func resize(_ action: String, _ title: String, _ keys: KeySequence) -> CommandSpec {
        spec(action, title, keys, entryPoints: [.leader, .palette, .menuBar])
    }

    private static func move(_ action: String, _ title: String, _ keys: KeySequence) -> CommandSpec {
        spec(action, title, keys, entryPoints: [.leader, .palette])
    }

    private static func spec(_ action: String, _ title: String, _ keys: KeySequence,
                             entryPoints: Set<EntryPoint>) -> CommandSpec {
        CommandSpec(id: CommandID(rawValue: "layout.\(action)"), module: module, titleKey: title,
                    leaderKeys: [keys], entryPoints: entryPoints, target: .focusedWindow, lingersAfterRun: true)
    }
}
