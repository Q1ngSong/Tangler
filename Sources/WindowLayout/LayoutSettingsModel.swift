import CoreKit
import Contracts
import Foundation
import Observation

/// Backs the layout settings page: every change is saved right away, and the module picks it
/// up through `SettingsStore.changes`.
@MainActor
@Observable
final class LayoutSettingsModel {
    struct ModifierChoice: Identifiable, Equatable {
        var title: String
        var modifiers: Modifiers
        var id: UInt8 { modifiers.rawValue }
    }

    static let desktopSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!
    /// The Keyboard pane. The shortcuts sheet inside it has no link that works on every system,
    /// so the page says where to click from there.
    static let keyboardSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
    /// The system shortcuts to untick, as "键盘快捷键… › 调度中心" names them.
    static var systemDesktopShortcuts: [String] { [L10n.text("windowlayout.move.left.a.space"), L10n.text("windowlayout.move.right.a.space"), L10n.text("windowlayout.switch.to.desktop")] }

    private var stored: LayoutSettings
    private(set) var tiling: SystemTiling
    /// Whether the page lists the system shortcuts to untick: once their settings were opened.
    private(set) var showsSystemDesktopShortcuts = false
    @ObservationIgnored private let store: any SettingsStore
    @ObservationIgnored private let readTiling: () -> SystemTiling
    @ObservationIgnored private let openURL: (URL) -> Void

    init(store: any SettingsStore, readTiling: @escaping () -> SystemTiling, openURL: @escaping (URL) -> Void) {
        self.store = store
        self.readTiling = readTiling
        self.openURL = openURL
        stored = store.load(LayoutSettings.self)
        tiling = readTiling()
    }

    var settings: LayoutSettings {
        get { stored }
        set {
            guard newValue != stored else { return }
            stored = newValue
            store.save(newValue)
        }
    }

    var conflicts: [String] { tiling.conflicts(with: stored) }

    /// The common choices, plus the stored one when it is something else.
    var modifierChoices: [ModifierChoice] {
        var choices = [
            ModifierChoice(title: "⌥ Option", modifiers: .option),
            ModifierChoice(title: "⌃ Control", modifiers: .control),
            ModifierChoice(title: "⌘ Command", modifiers: .command),
            ModifierChoice(title: "⇧ Shift", modifiers: .shift),
            ModifierChoice(title: "⌃⌥ Control + Option", modifiers: [.control, .option]),
        ]
        if !choices.contains(where: { $0.modifiers == stored.gridModifiers }) {
            choices.append(ModifierChoice(title: stored.gridModifiers.description, modifiers: stored.gridModifiers))
        }
        return choices
    }

    func refreshTiling() {
        tiling = readTiling()
    }

    func openSystemSettings() {
        openURL(Self.desktopSettingsURL)
    }

    /// Opens the Keyboard settings and lists what to untick there. Nothing is changed: turning
    /// the system's shortcuts off is the user's to do.
    func openKeyboardSettings() {
        showsSystemDesktopShortcuts = true
        openURL(Self.keyboardSettingsURL)
    }
}
