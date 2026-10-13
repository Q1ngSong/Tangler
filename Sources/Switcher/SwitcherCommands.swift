import CoreKit
import Contracts

/// The switcher opens from global shortcuts only; finding windows by name is the palette's job.
/// The shifted shortcuts open at the far end of the list. They need commands of their own:
/// the system's ⇧⌘Tab goes off together with ⌘Tab, and shortcuts match their modifiers exactly.
enum SwitcherCommands {
    static let module: ModuleID = "switcher"
    static let allWindows: CommandID = "switcher.allWindows"
    static let appWindows: CommandID = "switcher.appWindows"
    static let allWindowsReverse: CommandID = "switcher.allWindowsReverse"
    static let appWindowsReverse: CommandID = "switcher.appWindowsReverse"

    static let all: [CommandSpec] = [
        CommandSpec(id: allWindows, module: module, titleKey: "switcher.switch.windows",
                    globalShortcut: KeyChord(.tab, modifiers: .command), entryPoints: []),
        CommandSpec(id: appWindows, module: module, titleKey: "switcher.switch.windows.of.the.same.app",
                    globalShortcut: KeyChord(.backtick, modifiers: .command), entryPoints: []),
        CommandSpec(id: allWindowsReverse, module: module, titleKey: "switcher.switch.windows.in.reverse",
                    globalShortcut: KeyChord(.tab, modifiers: [.command, .shift]), entryPoints: []),
        CommandSpec(id: appWindowsReverse, module: module, titleKey: "switcher.switch.same.app.windows.in.reverse",
                    globalShortcut: KeyChord(.backtick, modifiers: [.command, .shift]), entryPoints: []),
    ]

    /// The switcher a command opens.
    static func opening(_ id: CommandID) -> (kind: SwitcherKind, reverse: Bool)? {
        switch id {
        case allWindows: return (.allWindows, false)
        case appWindows: return (.appWindows, false)
        case allWindowsReverse: return (.allWindows, true)
        case appWindowsReverse: return (.appWindows, true)
        default: return nil
        }
    }
}
