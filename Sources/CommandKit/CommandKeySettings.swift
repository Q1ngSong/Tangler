import Contracts

/// The user's key overrides, keyed by command ID string so they stay readable as JSON.
/// Overrides for commands that are not registered wait until their module starts.
public struct CommandKeySettings: ModuleSettings {
    public static let moduleID: ModuleID = "commands"
    public static let version = 1
    public static let defaultValue = CommandKeySettings()

    /// Replaces a command's declared leader keys; an empty list takes it off the leader.
    public var leaderKeys: [String: [KeySequence]]
    /// Replaces a command's declared global shortcut. A nil value turns the shortcut off;
    /// removing the entry goes back to the declared one.
    public var globalShortcuts: [String: KeyChord?]

    public init(leaderKeys: [String: [KeySequence]] = [:], globalShortcuts: [String: KeyChord?] = [:]) {
        self.leaderKeys = leaderKeys
        self.globalShortcuts = globalShortcuts
    }
}
