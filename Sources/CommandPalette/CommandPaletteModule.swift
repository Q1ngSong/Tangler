import Contracts
import CoreKit
import SwiftUI

/// Leader mode with its hint panel, and the search palette (design section 4.2).
@MainActor
public final class CommandPaletteModule: FeatureModule {
    public static let moduleID = PaletteCommands.module
    public static var displayName: String { L10n.text("commandpalette.command.search") }
    public static var declaredCommands: [CommandSpec] { PaletteCommands.all }
    public static var settingsType: (any ModuleSettings.Type)? { PaletteSettings.self }

    /// Shared by leader mode and the palette: what was used last comes first in the palette.
    let recency = RecencyLog()
    private let context: ModuleContext
    private let hud: LeaderHUD
    private let leader: LeaderMode
    private let palette: PaletteController
    private var isRunning = false
    private var tasks: [Task<Void, Never>] = []

    public convenience init(context: ModuleContext) {
        self.init(context: context, environment: .live())
    }

    init(context: ModuleContext, environment: PaletteEnvironment) {
        self.context = context
        let areas = OverlayAreaFinder(windows: context.windows, pointer: environment.pointer)
        hud = LeaderHUD(presenter: environment.leaderPresenter, scheduler: environment.scheduler)
        leader = LeaderMode(context: context, hud: hud, areas: areas, scheduler: environment.scheduler)
        palette = PaletteController(context: context, presenter: environment.palettePresenter, hud: hud,
                                    areas: areas, recency: recency)
        leader.onRun = { [recency] id in recency.touch(.command(id)) }
    }

    public func start() async throws {
        try context.commands.register(PaletteCommands.open) { [weak self] command in
            guard let self else { return .unavailable(reason: L10n.text("commandpalette.command.search.is.disabled")) }
            return await openPalette(command)
        }
        isRunning = true
        leader.isEnabled = true
        palette.isEnabled = true
        // Subscribe before loading so a save in between is not lost.
        let changes = context.settings.changes(PaletteSettings.self)
        apply(context.settings.load(PaletteSettings.self))
        let leaderEvents = context.input.events(.leader)
        let windowEvents = context.windows.events()
        tasks = [
            Task { [weak self] in
                for await value in changes { self?.apply(value) }
            },
            Task { [weak self] in
                for await event in leaderEvents {
                    switch event {
                    case .leaderTriggered:
                        await self?.leaderTriggered()
                    case .shortcut, .mouseDown, .mouseDragged, .mouseUp, .mouseMoved, .modifiersChanged, .scroll:
                        break
                    }
                }
            },
            Task { [weak self] in
                for await event in windowEvents { self?.windowChanged(event) }
            },
        ]
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(PaletteSettingsView(store: context.settings))
    }

    public func stop() async {
        isRunning = false
        for task in tasks { task.cancel() }
        tasks = []
        leader.isEnabled = false
        palette.isEnabled = false
        hud.hide()
        context.input.setLeaderTrigger(nil)
        context.commands.unregisterAll(module: Self.moduleID)
    }

    private func apply(_ settings: PaletteSettings) {
        guard isRunning else { return }
        context.input.setLeaderTrigger(settings.leaderTrigger)
        leader.holdsTrigger = settings.leaderTrigger == .holdRightCommand
        leader.lingerSeconds = settings.effectiveLingerSeconds
    }

    /// The palette acts on the window focused before it opened: the leader's target, or, from the
    /// menu bar, the window focused now.
    private func openPalette(_ command: CommandContext) async -> CommandResult {
        // Leader mode would swallow the typing meant for the search field.
        leader.exit()
        var target = command.targetWindow
        if target == nil { target = await context.windows.focusedWindowID() }
        await palette.open(target: target)
        return .done
    }

    /// The leader key leaves the palette the way it leaves leader mode.
    private func leaderTriggered() async {
        DiagnosticLog("leader").trace("收到总入口键：搜索面板\(palette.isOpen ? "开着" : "关着")，入口模式\(leader.isActive ? "开着" : "关着")")
        if palette.isOpen {
            palette.cancel()
        } else {
            await leader.toggle()
        }
    }

    private func windowChanged(_ event: WindowEvent) {
        switch event {
        case .focused(let id):
            recency.touch(.window(id))
        case .disappeared(let id):
            recency.forget(.window(id))
            palette.windowDisappeared(id)
        case .appeared, .moved, .resized, .minimized, .restored, .titleChanged, .currentSpaceChanged,
             .spacesChanged, .displaysChanged, .exposeChanged, .appLaunched, .appTerminated, .appHidden, .appUnhidden:
            break
        }
    }
}
