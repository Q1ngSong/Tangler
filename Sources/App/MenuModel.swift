import CoreKit
import Contracts

struct MenuEntry: Equatable {
    /// A dynamic command's entry carries that command's ID.
    let id: CommandID
    let title: String
    /// How to reach the command from the keyboard, e.g. "入口键 ←" or "⌘Tab".
    let keys: String
    /// The SF Symbol before the title; the menu shows it only in Liquid Glass.
    var symbol: String? = nil
    var isChecked = false
    /// The dynamic command the entry runs; nil for a registered command.
    var dynamic: DynamicCommand? = nil
}

struct MenuSection: Equatable {
    let title: String
    let entries: [MenuEntry]
}

/// The status bar menu's commands: those offered in the menu bar, grouped by module. A module's
/// dynamic commands that say how they show in the menu come first in its section.
enum MenuModel {
    static func sections(for commands: [CommandSpec], dynamic: [DynamicCommand] = [],
                         modules: [(id: ModuleID, name: String)]) -> [MenuSection] {
        modules.compactMap { module in
            let changing = dynamic.filter { $0.module == module.id }.compactMap { command in
                command.menu.map { item in
                    MenuEntry(id: CommandID(rawValue: command.id), title: item.title, keys: "", isChecked: item.isChecked,
                              dynamic: command)
                }
            }
            let fixed = commands
                .filter { $0.module == module.id && $0.entryPoints.contains(.menuBar) }
                .map { MenuEntry(id: $0.id, title: $0.title, keys: keys(for: $0), symbol: symbols[$0.id]) }
            let entries = changing + fixed
            return entries.isEmpty ? nil : MenuSection(title: module.name, entries: entries)
        }
    }

    static func keys(for spec: CommandSpec) -> String {
        if let shortcut = spec.globalShortcut { return shortcut.description }
        if let sequence = spec.leaderKeys.first { return L10n.text("app.leader") + sequence.description }
        return ""
    }

    /// Symbols for the commands in the menu, as Tahoe menus show them (Liquid Glass skin design
    /// 4.3). Kept in the App, so Contracts and the modules stay as they are.
    static let symbols: [CommandID: String] = [
        "layout.leftHalf": "rectangle.lefthalf.filled",
        "layout.rightHalf": "rectangle.righthalf.filled",
        "layout.topHalf": "rectangle.tophalf.filled",
        "layout.bottomHalf": "rectangle.bottomhalf.filled",
        "layout.topLeft": "rectangle.inset.topleft.filled",
        "layout.topRight": "rectangle.inset.topright.filled",
        "layout.bottomLeft": "rectangle.inset.bottomleft.filled",
        "layout.bottomRight": "rectangle.inset.bottomright.filled",
        "layout.maximize": "arrow.up.left.and.arrow.down.right",
        "layout.center": "rectangle.center.inset.filled",
        "layout.restore": "arrow.uturn.backward",
        "palette.open": "magnifyingglass",
        "workspace.save": "square.stack.3d.down.right",
        "tabs.mergeArea": "rectangle.topthird.inset.filled",
        "tabs.remove": "rectangle.badge.minus",
    ]

    static let settingsSymbol = "gearshape"
    static let quitSymbol = "power"
}
