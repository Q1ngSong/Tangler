import Contracts
import CoreKit

/// The App's command registry (design sections 3.3 and 3.5). Feature modules register their
/// declared commands here; the leader hints, the palette and the menu bar read them back with
/// the user's key overrides (`CommandKeySettings`) applied.
@MainActor
public final class LiveCommandRegistry: CommandRegistry {
    public private(set) var commands: [CommandSpec] = []
    public private(set) var groups: [LeaderGroup] = []
    /// Keys that are not in effect, with the reason; empty when every override applies.
    public private(set) var overrideProblems: [OverrideProblem] = []

    private let input: any InputService
    /// As registered, in registration order; `commands` is these with the overrides applied.
    private var declared: [CommandSpec] = []
    private var handlers: [CommandID: CommandHandler] = [:]
    private var keySettings: CommandKeySettings
    private var bindings = ShortcutBindings()
    private var sources: [any DynamicCommandSource] = []
    private var tasks: [Task<Void, Never>] = []
    private let log = DiagnosticLog("commands")

    public init(input: any InputService, settings: any SettingsStore) {
        self.input = input
        // Subscribe before loading so a save in between is not lost.
        let keyChanges = settings.changes(CommandKeySettings.self)
        keySettings = settings.load(CommandKeySettings.self)
        let shortcutEvents = input.events(.shortcuts)
        tasks = [
            Task { [weak self] in
                for await value in keyChanges { self?.keySettingsChanged(value) }
            },
            Task { [weak self] in
                for await event in shortcutEvents {
                    switch event {
                    case .shortcut(let id):
                        self?.shortcutPressed(CommandID(rawValue: id))
                    case .leaderTriggered, .mouseDown, .mouseDragged, .mouseUp, .mouseMoved, .modifiersChanged, .scroll:
                        break
                    }
                }
            },
        ]
    }

    deinit {
        for task in tasks { task.cancel() }
    }

    public func register(_ spec: CommandSpec, handler: @escaping CommandHandler) throws {
        guard handlers[spec.id] == nil else { throw CommandRegistryError.duplicate(spec.id) }
        // Declared keys only, so a user's overrides can never keep a module from starting.
        if let conflict = CommandCatalog.conflict(between: spec, and: declared) {
            throw CommandRegistryError.conflict(conflict)
        }
        declared.append(spec)
        handlers[spec.id] = handler
        let applied = refresh()
        if let chord = spec.globalShortcut, let reason = applied.declaredChordsTaken[spec.id] {
            declared.removeLast()
            handlers[spec.id] = nil
            refresh()
            throw CommandRegistryError.conflict(L10n.text("commandkit.global.shortcut", String(describing: (chord)), String(describing: (reason))))
        }
    }

    public func registerGroup(_ group: LeaderGroup) throws {
        guard !groups.contains(where: { $0.prefix == group.prefix }) else {
            throw CommandRegistryError.conflict(L10n.text("commandkit.duplicate.group", String(describing: (group.prefix))))
        }
        groups.append(group)
    }

    public func unregisterAll(module: ModuleID) {
        for spec in declared where spec.module == module { handlers[spec.id] = nil }
        declared.removeAll { $0.module == module }
        groups.removeAll { $0.module == module }
        refresh()
    }

    public func addDynamicSource(_ source: any DynamicCommandSource) {
        sources.append(source)
    }

    public func removeDynamicSources(module: ModuleID) {
        sources.removeAll { $0.moduleID == module }
    }

    public func perform(_ id: CommandID, context: CommandContext) async -> CommandResult {
        guard let handler = handlers[id] else {
            log.problem("命令 \(id.rawValue) 未注册")
            return .unavailable(reason: L10n.text("commandkit.command.is.not.registered", String(describing: (id))))
        }
        log.trace("执行 \(id.rawValue)（目标窗口 \(context.targetWindow.map { String($0.rawValue) } ?? "无")，第 \(context.repeatIndex + 1) 次）")
        let result = await handler(context)
        log.trace("\(id.rawValue) 结果：\(result)")
        return result
    }

    public func resolveLeader(_ keys: [Key]) -> LeaderResolution {
        LeaderMatcher.resolve(keys, commands: commands, groups: groups)
    }

    public func dynamicCommands() async -> [DynamicCommand] {
        var all: [DynamicCommand] = []
        for source in sources { all += await source.dynamicCommands() }
        return all
    }

    /// Goes to the module's source that still lists the command, so one that has gone away
    /// meanwhile (say, a deleted workspace) is reported instead of reaching the module.
    public func performDynamic(_ command: DynamicCommand) async -> CommandResult {
        for source in sources where source.moduleID == command.module {
            if await source.dynamicCommands().contains(where: { $0.id == command.id }) {
                return await source.perform(command)
            }
        }
        return .unavailable(reason: L10n.text("commandkit.no.longer.exists", String(describing: (command.title))))
    }

    /// Runs in a task of its own so a long handler, such as a switcher session, never holds up
    /// the next shortcut. The context has no target window, so a focused-window command's
    /// handler has to look up the focused window itself.
    private func shortcutPressed(_ id: CommandID) {
        guard bindings.bound[id] != nil else {
            log.trace("快捷键 \(id.rawValue) 没有绑定的命令，忽略")
            return
        }
        Task { _ = await perform(id, context: CommandContext()) }
    }

    private func keySettingsChanged(_ value: CommandKeySettings) {
        keySettings = value
        refresh()
    }

    /// Applies the overrides to the declared commands and brings InputService in line. A chord
    /// InputService refuses belongs to another client, so it is applied again with that chord
    /// taken; the taken set only grows, so this ends.
    @discardableResult
    private func refresh() -> KeyOverrides.Result {
        var taken: [KeyChord: String] = [:]
        while true {
            let applied = KeyOverrides.apply(keySettings, to: declared, takenChords: taken)
            let refused = bindings.update(to: applied.commands, input: input)
            if refused.isEmpty {
                commands = applied.commands
                overrideProblems = applied.problems
                return applied
            }
            taken.merge(refused) { kept, _ in kept }
        }
    }
}
