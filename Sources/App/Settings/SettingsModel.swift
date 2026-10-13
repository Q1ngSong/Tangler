import CoreKit
import CommandKit
import CommandPalette
import Contracts
import Observation
import OverlayKit
import ServiceManagement
import SwiftUI
import WindowKit

enum SettingsPage: Hashable {
    case general, shortcuts, diagnostics
    case module(ModuleID)
}

/// State behind the settings window. Reads come from the services; `refresh()` re-reads
/// what can change outside the window (permissions, login item).
@MainActor @Observable
final class SettingsModel {
    var page: SettingsPage = .general
    private(set) var accessibilityGranted = false
    private(set) var screenRecordingGranted = false
    private(set) var launchAtLogin = false
    private(set) var launchAtLoginProblem: String?
    private(set) var appSettings = AppSettings.defaultValue
    private(set) var keySettings = CommandKeySettings.defaultValue
    private(set) var leaderTrigger = LeaderTrigger.holdRightCommand

    let updates: AppUpdates?
    @ObservationIgnored let composition: Composition
    /// Where overlays read the skin from; tests pass their own instance.
    @ObservationIgnored let skin: CurrentSkin
    /// Called after the skin changes, so the window controller can rebuild the window.
    @ObservationIgnored var onSkinChange: ((Skin) -> Void)?

    /// `skin` defaults to `CurrentSkin.shared`; tests pass their own instance.
    init(composition: Composition, skin: CurrentSkin? = nil, updates: AppUpdates? = nil) {
        self.updates = updates
        self.composition = composition
        self.skin = skin ?? .shared
        refresh()
    }

    /// The login item is read only with `loginItem`: it is a call to another process, too slow
    /// for the main thread every two seconds, and it changes only through this window or
    /// System Settings, which showing the window or making it key catches.
    func refresh(loginItem: Bool = true) {
        accessibilityGranted = composition.windows.isAuthorized
        screenRecordingGranted = composition.capture.isAuthorized
        if loginItem { launchAtLogin = SMAppService.mainApp.status == .enabled }
        appSettings = composition.settings.load(AppSettings.self)
        keySettings = composition.settings.load(CommandKeySettings.self)
        leaderTrigger = composition.settings.load(PaletteSettings.self).leaderTrigger
    }

    // MARK: Permissions

    func requestAccessibility() {
        _ = composition.windows.requestAccessibilityPermission()
        refresh()
    }

    func requestScreenRecording() {
        Permissions.requestScreenRecording()
        refresh()
    }

    // MARK: General

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLoginProblem = nil
        } catch {
            launchAtLoginProblem = L10n.text("app.could.not.change.the.setting", String(describing: (error.localizedDescription)))
        }
        if SMAppService.mainApp.status == .requiresApproval {
            launchAtLoginProblem = L10n.text("app.allow.tangler.in.system.settings.general.login")
        }
        refresh()
    }

    func setModule(_ id: ModuleID, enabled: Bool) {
        if enabled { appSettings.disabledModules.remove(id.rawValue) } else { appSettings.disabledModules.insert(id.rawValue) }
        composition.settings.save(appSettings)
    }

    /// Saves the skin and applies it at once: overlays on screen redraw, and the window is rebuilt.
    func setSkin(_ value: Skin) {
        guard appSettings.skin != value else { return }
        appSettings.skin = value
        composition.settings.save(appSettings)
        skin.value = value
        onSkinChange?(value)
    }

    func setLanguage(_ language: AppLanguage) {
        guard appSettings.language != language else { return }
        appSettings.language = language
        composition.settings.save(appSettings)
        L10n.configure(language)
    }

    // MARK: Shortcuts

    /// Declared commands, in module order, so the page lists every command even when its
    /// module is turned off.
    var declaredCommands: [(module: String, specs: [CommandSpec])] {
        FeatureCatalog.all.map { (module: $0.displayName, specs: $0.declaredCommands) }.filter { !$0.specs.isEmpty }
    }

    /// Every preview resolves the same effective bindings used by the command registry.
    var previewInputBindings: SettingsInputBindings {
        let registered = composition.commands.commands
        let commands = declaredCommands.flatMap(\.specs).map { declared in
            if let running = registered.first(where: { $0.id == declared.id }) { return running }
            var spec = declared
            spec.globalShortcut = shortcut(for: declared)
            spec.leaderKeys = leaderKeys(for: declared)
            return spec
        }
        return SettingsInputBindings(trigger: leaderTrigger, commands: commands)
    }

    /// The shortcut in effect: the user's override when there is one, otherwise the declared one.
    func shortcut(for spec: CommandSpec) -> KeyChord? {
        if let override = keySettings.globalShortcuts[spec.id.rawValue] { return override }
        return spec.globalShortcut
    }

    func isOverridden(_ spec: CommandSpec) -> Bool { keySettings.globalShortcuts[spec.id.rawValue] != nil }

    /// Running commands expose validated bindings; disabled modules keep their saved choice visible.
    func leaderKeys(for spec: CommandSpec) -> [KeySequence] {
        composition.commands.commands.first { $0.id == spec.id }?.leaderKeys
            ?? keySettings.leaderKeys[spec.id.rawValue] ?? spec.leaderKeys
    }

    /// Reject known conflicts before Save; the registry remains the final authority at registration.
    func shortcutProblem(_ chord: KeyChord?, for spec: CommandSpec, trigger: LeaderTrigger) -> String? {
        guard let chord else { return nil }
        if case .chord(let leaderChord) = trigger, leaderChord == chord { return L10n.text("app.conflicts.with.the.leader.key") }
        if let other = declaredCommands.flatMap(\.specs).first(where: {
            $0.id != spec.id && shortcut(for: $0) == chord
        }) {
            return L10n.text("app.already.used.by", String(describing: (other.title)))
        }
        return nil
    }

    func setShortcut(_ chord: KeyChord?, for spec: CommandSpec) {
        keySettings.globalShortcuts[spec.id.rawValue] = .some(chord)
        composition.settings.save(keySettings)
    }

    func resetShortcut(for spec: CommandSpec) {
        keySettings.globalShortcuts.removeValue(forKey: spec.id.rawValue)
        composition.settings.save(keySettings)
    }

    /// Global shortcuts would swallow the chord being recorded, so pause them meanwhile.
    func setRecording(_ recording: Bool) {
        composition.input.setShortcutsSuspended(recording)
    }

    var overrideProblems: [OverrideProblem] { composition.commands.overrideProblems }

    // MARK: Modules and diagnostics

    func settingsView(for id: ModuleID) -> AnyView? {
        composition.runner.running.first { type(of: $0).moduleID == id }?.makeSettingsView()
    }

    func isRunning(_ id: ModuleID) -> Bool {
        composition.runner.running.contains { type(of: $0).moduleID == id }
    }

    var capabilityStatuses: [WindowCapabilityStatus] { composition.windows.capabilityStatuses }
    var failures: [ModuleID: String] { composition.runner.failures }
}
