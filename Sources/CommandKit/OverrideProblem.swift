import Contracts

/// A key that is not in effect, and why, for the shortcut settings page. Usually a user
/// override, and the command keeps its declared keys; otherwise a declared shortcut that
/// another input client holds, and the command has no shortcut.
public struct OverrideProblem: Hashable, Sendable {
    public enum Field: Hashable, Sendable {
        case leaderKeys, globalShortcut
    }

    public var command: CommandID
    public var field: Field
    public var reason: String
}
