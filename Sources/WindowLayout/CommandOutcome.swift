import CoreKit
import Contracts
import CoreGraphics

/// A command that stops early, carrying what the user is told.
struct CommandRefusal: Error {
    let result: CommandResult

    static func failed(_ reason: String) -> CommandRefusal { CommandRefusal(result: .failed(reason: reason)) }
    static func unavailable(_ reason: String) -> CommandRefusal { CommandRefusal(result: .unavailable(reason: reason)) }
}

extension WindowError {
    /// Missing permissions or abilities grey a command out; everything else is a failure.
    var commandResult: CommandResult {
        switch self {
        case .notAuthorized: return .unavailable(reason: L10n.text("commandpalette.accessibility.access.is.required"))
        case .windowNotFound: return .failed(reason: L10n.text("tabgroups.the.window.could.not.be.found.it"))
        case .appNotResponding: return .failed(reason: L10n.text("commandpalette.the.application.is.not.responding"))
        case .rejected(let reason): return .failed(reason: reason)
        case .unsupported(let reason): return .unavailable(reason: reason)
        }
    }
}

extension Result where Success == CGRect, Failure == WindowError {
    var commandResult: CommandResult {
        switch self {
        case .success: return .done
        case .failure(let error): return error.commandResult
        }
    }
}

extension Direction {
    /// As in "左侧没有其他显示器".
    var sideName: String {
        switch self {
        case .left: return L10n.text("windowlayout.left")
        case .right: return L10n.text("windowlayout.right")
        case .up: return L10n.text("windowlayout.above")
        case .down: return L10n.text("windowlayout.below")
        }
    }
}
