import CommandPalette
import Contracts
import DockPreview
import Switcher
import TabGroups
import WindowLayout
import Workspaces

/// Every feature module the App runs, in the order menus and settings list them.
@MainActor
enum FeatureCatalog {
    static let all: [any FeatureModule.Type] = [
        WindowLayoutModule.self, TabGroupsModule.self, SwitcherModule.self, DockPreviewModule.self,
        CommandPaletteModule.self, WorkspacesModule.self,
    ]

    static var names: [(id: ModuleID, name: String)] { all.map { (id: $0.moduleID, name: $0.displayName) } }

    /// For a module without a symbol of its own.
    static let fallbackSymbol = "puzzlepiece.extension"

    /// The SF Symbol for a module's sidebar row and placeholder page in Liquid Glass (Liquid Glass
    /// skin design 4.2). Kept in the App, so the modules and Contracts stay as they are.
    static func symbol(for id: ModuleID) -> String { symbols[id] ?? fallbackSymbol }

    private static let symbols: [ModuleID: String] = [
        WindowLayoutModule.moduleID: "rectangle.split.2x1",
        TabGroupsModule.moduleID: "macwindow",
        SwitcherModule.moduleID: "rectangle.stack",
        DockPreviewModule.moduleID: "dock.rectangle",
        CommandPaletteModule.moduleID: "magnifyingglass",
        WorkspacesModule.moduleID: "square.stack.3d.up",
    ]
}
