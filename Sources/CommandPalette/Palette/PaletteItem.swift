import CoreKit
import Contracts

/// Identifies a palette row across searches, so the selection and the recently-used order
/// survive new results.
enum PaletteItemID: Hashable, Sendable {
    case window(WindowID)
    case command(CommandID)
    case dynamic(module: ModuleID, id: String)
}

/// One row of the search palette: a window to switch to or a command to run.
struct PaletteItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case window(WindowInfo)
        /// `argument` is the number typed after the name, for a command that takes a digit.
        case command(CommandSpec, argument: Int?)
        case dynamic(DynamicCommand)
    }

    var kind: Kind

    var id: PaletteItemID {
        switch kind {
        case .window(let window): return .window(window.id)
        case .command(let spec, _): return .command(spec.id)
        case .dynamic(let command): return .dynamic(module: command.module, id: command.id)
        }
    }

    var title: String {
        switch kind {
        case .window(let window): return window.title.isEmpty ? window.appName : window.title
        case .command(let spec, let argument): return argument.map { Self.title(spec.title, filledWith: $0) } ?? spec.title
        case .dynamic(let command): return command.title
        }
    }

    var subtitle: String? {
        switch kind {
        case .window(let window): return window.isMinimized ? L10n.text("commandpalette.minimized", String(describing: (window.appName))) : window.appName
        case .command: return needsNumber ? L10n.text("commandpalette.enter.a.number.after.the.name") : nil
        case .dynamic: return nil
        }
    }

    /// The command's current leader keys, one key cap each; the palette and the hints read the
    /// same registry, so a changed key shows here too.
    var keys: [String] {
        guard case .command(let spec, _) = kind, let sequence = spec.leaderKeys.first else { return [] }
        return sequence.patterns.map { $0 == .anyDigit ? "0–9" : $0.description }
    }

    var shortcut: String? {
        guard case .command(let spec, _) = kind else { return nil }
        return spec.globalShortcut?.description
    }

    /// A command that takes a digit, e.g. 移到第 N 个桌面, found without one.
    var needsNumber: Bool {
        guard case .command(let spec, nil) = kind else { return false }
        return Self.takesNumber(spec)
    }

    static func takesNumber(_ spec: CommandSpec) -> Bool {
        spec.leaderKeys.contains { $0.patterns.contains(.anyDigit) }
    }

    /// "移到第 N 个桌面" with 3 reads "移到第 3 个桌面"; a title without an N gets the number appended.
    static func title(_ title: String, filledWith number: Int) -> String {
        var words = title.components(separatedBy: " ")
        guard let index = words.firstIndex(of: "N") else { return "\(title) \(number)" }
        words[index] = String(number)
        return words.joined(separator: " ")
    }
}
