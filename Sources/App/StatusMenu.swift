import CoreKit
import AppKit
import Contracts
import OverlayKit

/// The menu bar icon. The menu is rebuilt each time it opens, so key changes show at once.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate, NSMenuItemValidation {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let composition: Composition
    private let updates: AppUpdates?
    private let openSettings: () -> Void
    /// The dynamic commands as last read. Reading them is asynchronous and a menu must be filled
    /// before it opens, so it opens with these and is filled again when the answer differs.
    private var dynamic: [DynamicCommand] = []

    init(composition: Composition, updates: AppUpdates? = nil, openSettings: @escaping () -> Void) {
        self.composition = composition
        self.updates = updates
        self.openSettings = openSettings
        super.init()
        statusItem.button?.image = TanglerMark.menuBarImage()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        fill(menu)
        Task { [weak self] in
            guard let self else { return }
            let fresh = await composition.commands.dynamicCommands()
            guard fresh != dynamic else { return }
            dynamic = fresh
            fill(menu)
        }
    }

    private func fill(_ menu: NSMenu) {
        menu.removeAllItems()
        // Tahoe menus put a symbol before each item; the classic skin keeps them plain (Liquid
        // Glass skin design 4.3).
        let showsSymbols = CurrentSkin.shared.value == .liquidGlass
        func image(_ symbol: String?) -> NSImage? {
            guard showsSymbols, let symbol else { return nil }
            return NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        let sections = MenuModel.sections(for: composition.commands.commands, dynamic: dynamic, modules: FeatureCatalog.names)
        for section in sections {
            menu.addItem(NSMenuItem.sectionHeader(title: section.title))
            for entry in section.entries {
                let item = NSMenuItem(title: entry.title, action: #selector(run(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = entry
                item.subtitle = entry.keys
                item.state = entry.isChecked ? .on : .off
                item.image = image(entry.symbol)
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }
        let settingsItem = menu.addItem(withTitle: L10n.text("app.settings"), action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = image(MenuModel.settingsSymbol)
        if let updates {
            let title = updates.availableVersion.map { L10n.text("app.update.to", String(describing: ($0))) } ?? L10n.text("app.check.for.updates")
            let updateItem = menu.addItem(withTitle: title, action: #selector(checkForUpdates), keyEquivalent: "")
            updateItem.target = self
            updateItem.image = image("arrow.triangle.2.circlepath")
        }
        menu.addItem(.separator())
        let quitItem = menu.addItem(withTitle: L10n.text("app.quit.tangler"), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitItem.image = image(MenuModel.quitSymbol)
    }

    @objc private func run(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? MenuEntry else { return }
        Task {
            if let command = entry.dynamic {
                _ = await composition.commands.performDynamic(command)
            } else {
                _ = await composition.perform(entry.id)
            }
        }
    }

    @objc private func showSettings() { openSettings() }

    @objc private func checkForUpdates() { updates?.checkForUpdates() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdates) { return updates?.canCheckForUpdates == true }
        return true
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
