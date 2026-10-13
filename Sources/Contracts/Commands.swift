import CoreKit

/// Where a command can be triggered.
public enum EntryPoint: String, Codable, CaseIterable, Comparable, Sendable {
    case leader, palette, menuBar

    public static func < (lhs: EntryPoint, rhs: EntryPoint) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

public enum CommandTarget: String, Codable, Sendable {
    case none
    /// The window that was focused when the leader key or the palette opened.
    case focusedWindow
}

/// One command a feature module offers (design section 3.5). Modules declare their
/// commands statically so the registry, the leader hints, the palette, the menu bar
/// and COMMANDS.md all read the same list.
public struct CommandSpec: Hashable, Codable, Sendable {
    public var id: CommandID
    public var module: ModuleID
    private var fallbackTitle: String
    public var titleKey: String?
    public var title: String {
        get { titleKey.map { L10n.text($0) } ?? fallbackTitle }
        set { fallbackTitle = newValue; titleKey = nil }
    }
    /// Extra search words; pinyin and initials of `title` are derived automatically.
    public var aliases: [String]
    public var leaderKeys: [KeySequence]
    /// Never includes `.function`; input matching ignores fn and Caps Lock.
    public var globalShortcut: KeyChord?
    public var entryPoints: Set<EntryPoint>
    public var target: CommandTarget
    /// Stay in leader mode for the linger period after running, so repeats can cycle.
    public var lingersAfterRun: Bool

    public init(id: CommandID, module: ModuleID, title: String = "", titleKey: String? = nil, aliases: [String] = [],
                leaderKeys: [KeySequence] = [], globalShortcut: KeyChord? = nil,
                entryPoints: Set<EntryPoint>, target: CommandTarget = .none, lingersAfterRun: Bool = false) {
        self.id = id
        self.module = module
        self.titleKey = titleKey
        self.fallbackTitle = title
        self.aliases = aliases
        self.leaderKeys = leaderKeys
        self.globalShortcut = globalShortcut
        self.entryPoints = entryPoints
        self.target = target
        self.lingersAfterRun = lingersAfterRun
    }

    private enum CodingKeys: String, CodingKey {
        case id, module, titleKey, aliases, leaderKeys, globalShortcut, entryPoints, target, lingersAfterRun
        case fallbackTitle = "title"
    }

    public func localizedTitle(using localizer: Localizer) -> String {
        titleKey.map { localizer.text($0) } ?? title
    }

    /// Searching either language also preserves Chinese pinyin in the English interface.
    public var searchAliases: [String] {
        guard let titleKey else { return aliases }
        return aliases + [Localizer(language: .english).text(titleKey),
                          Localizer(language: .simplifiedChinese).text(titleKey)]
    }

}

public struct CommandContext: Equatable, Sendable {
    /// The window focused when the leader key or the palette opened. Nil when a global
    /// shortcut triggered the command; window commands then ask `focusedWindowID()`.
    public var targetWindow: WindowID?
    /// The digit typed for an `.anyDigit` position.
    public var argument: Int?
    /// 0 on the first run; 1, 2, … when the same command repeats during the linger period.
    /// Handlers use it to cycle sizes, e.g. 1/2 → 1/3 → 2/3.
    public var repeatIndex: Int

    public init(targetWindow: WindowID? = nil, argument: Int? = nil, repeatIndex: Int = 0) {
        self.targetWindow = targetWindow
        self.argument = argument
        self.repeatIndex = repeatIndex
    }
}

public enum CommandResult: Equatable, Sendable {
    case done
    /// Shown greyed out with the reason, e.g. "需要 macOS 26.4".
    case unavailable(reason: String)
    case failed(reason: String)
}

public typealias CommandHandler = @MainActor (CommandContext) async -> CommandResult

/// A name for a leader key prefix, e.g. "D" → "移到其他显示器". Every key that leads to
/// more keys needs one so the hint panel can label it; the commands under a prefix must
/// belong to the module that declares the group (design section 4.2).
public struct LeaderGroup: Hashable, Codable, Sendable {
    public var prefix: KeySequence
    public var module: ModuleID
    private var fallbackTitle: String
    public var titleKey: String?
    public var title: String {
        get { titleKey.map { L10n.text($0) } ?? fallbackTitle }
        set { fallbackTitle = newValue; titleKey = nil }
    }

    public init(prefix: KeySequence, module: ModuleID, title: String = "", titleKey: String? = nil) {
        self.prefix = prefix
        self.module = module
        self.titleKey = titleKey
        self.fallbackTitle = title
    }

    private enum CodingKeys: String, CodingKey {
        case prefix, module, titleKey
        case fallbackTitle = "title"
    }
}

/// A next key offered by the leader hint panel.
public struct LeaderOption: Equatable, Sendable {
    public var keys: String
    public var title: String
    /// True when the key opens a group (e.g. "D" for displays) instead of running a command.
    public var isGroup: Bool

    public init(keys: String, title: String, isGroup: Bool) {
        self.keys = keys
        self.title = title
        self.isGroup = isGroup
    }
}

public enum LeaderResolution: Equatable, Sendable {
    case command(CommandID, argument: Int?)
    /// The keys so far are a prefix; the hint panel shows the options.
    case prefix([LeaderOption])
    case noMatch
}

/// A command whose existence changes at runtime, e.g. one per saved workspace.
public struct DynamicCommand: Hashable, Sendable {
    /// How a command shows in the status bar menu.
    public struct MenuItem: Hashable, Sendable {
        public var title: String
        /// Ticked, e.g. a workspace that is open.
        public var isChecked: Bool

        public init(title: String, isChecked: Bool = false) {
            self.title = title
            self.isChecked = isChecked
        }
    }

    public var id: String
    public var module: ModuleID
    private var fallbackTitle: String
    public var titleKey: String?
    public var titleArguments: [String]
    public var title: String {
        get { titleKey.map { L10n.current.format($0, titleArguments) } ?? fallbackTitle }
        set { fallbackTitle = newValue; titleKey = nil }
    }
    public var aliases: [String]
    /// Nil keeps the command out of the status bar menu.
    public var menu: MenuItem?

    public init(id: String, module: ModuleID, title: String = "", titleKey: String? = nil,
                titleArguments: [String] = [], aliases: [String] = [], menu: MenuItem? = nil) {
        self.id = id
        self.module = module
        self.fallbackTitle = title
        self.titleKey = titleKey
        self.titleArguments = titleArguments
        self.aliases = aliases
        self.menu = menu
    }
}

@MainActor
public protocol DynamicCommandSource: AnyObject {
    var moduleID: ModuleID { get }
    func dynamicCommands() async -> [DynamicCommand]
    func perform(_ command: DynamicCommand) async -> CommandResult
}

public enum CommandRegistryError: Error, Equatable, Sendable {
    case duplicate(CommandID)
    case conflict(String)
}

/// Every registered command. Implemented by CommandKit (design section 3.3).
@MainActor
public protocol CommandRegistry: AnyObject {
    /// Registered commands with the user's key overrides applied.
    var commands: [CommandSpec] { get }
    var groups: [LeaderGroup] { get }
    func register(_ spec: CommandSpec, handler: @escaping CommandHandler) throws
    func registerGroup(_ group: LeaderGroup) throws
    /// Removes the module's commands and groups.
    func unregisterAll(module: ModuleID)
    func addDynamicSource(_ source: any DynamicCommandSource)
    func removeDynamicSources(module: ModuleID)
    func perform(_ id: CommandID, context: CommandContext) async -> CommandResult
    /// Resolves the keys typed after the leader trigger.
    func resolveLeader(_ keys: [Key]) -> LeaderResolution
    func dynamicCommands() async -> [DynamicCommand]
    func performDynamic(_ command: DynamicCommand) async -> CommandResult
}
