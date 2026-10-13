import CoreKit
import Foundation

/// What happened to each entry while a checkpoint was expanded (workspaces design 5.2).
struct ExpansionReport: Equatable {
    struct Entry: Equatable, Identifiable {
        /// The entry of the checkpoint.
        var id: UUID
        var label: String
        var state: State
        /// Something the user should know besides: how the window was chosen, or that it was not
        /// placed or grouped as saved.
        var note: String?
    }

    enum State: Hashable {
        /// Not handled yet, or waiting for its window.
        case waiting
        case alreadyHere
        case moved
        case opened
        case launched
        case notRunning
        case contentsNotOpened
        /// The application was asked for a window and refused, or could not be asked.
        case noNewWindow
        /// Its window is on another desktop and stays there.
        case notMoved
        /// The application was asked for a window, which did not come in time.
        case timedOut
        case cancelled

        /// The entry has a window on the desktop.
        var hasWindow: Bool {
            switch self {
            case .alreadyHere, .moved, .opened, .launched: return true
            case .waiting, .notRunning, .contentsNotOpened, .noNewWindow, .notMoved, .timedOut, .cancelled: return false
            }
        }

        var text: String {
            switch self {
            case .waiting: return L10n.text("workspaces.waiting")
            case .alreadyHere: return L10n.text("workspaces.already.on.the.desktop")
            case .moved: return L10n.text("workspaces.moved.here")
            case .opened: return L10n.text("workspaces.opened.a.new.window")
            case .launched: return L10n.text("workspaces.launched.the.app")
            case .notRunning: return L10n.text("workspaces.app.not.running")
            case .contentsNotOpened: return L10n.text("workspaces.contents.not.opened")
            case .noNewWindow: return L10n.text("workspaces.no.new.window.opened")
            case .notMoved: return L10n.text("workspaces.not.moved")
            case .timedOut: return L10n.text("workspaces.timed.out.waiting.for.a.window")
            case .cancelled: return L10n.text("windowkit.cancelled")
            }
        }
    }

    var workspaceID: UUID
    var workspaceName: String
    var entries: [Entry]
    /// What stopped or cut short the whole expansion, e.g. that the user left the desktop.
    var notice: String?
    var isFinished = false

    init(workspace: Workspace) {
        workspaceID = workspace.id
        workspaceName = workspace.name
        entries = workspace.windows.map { window in
            Entry(id: window.id, label: window.title.isEmpty ? window.appName : "\(window.appName) — \(window.title)",
                  state: .waiting)
        }
    }

    var settledCount: Int { entries.filter(\.state.hasWindow).count }

    /// "到位 3/5 个窗口：1 个没有运行，1 个超时。已经离开这个桌面".
    var summary: String {
        var problems: [String] = []
        func count(_ label: String, _ states: State...) {
            let number = entries.filter { states.contains($0.state) }.count
            if number > 0 { problems.append(L10n.text("workspaces.expansion.countWithStatus", String(describing: (number)), String(describing: (label)))) }
        }
        count(L10n.text("workspaces.not.running"), .notRunning)
        count(L10n.text("workspaces.contents.not.opened"), .contentsNotOpened)
        count(L10n.text("workspaces.without.a.new.window"), .noNewWindow)
        count(L10n.text("workspaces.not.moved"), .notMoved)
        count(L10n.text("workspaces.timed.out"), .timedOut)
        count(L10n.text("windowkit.cancelled"), .cancelled)
        count(L10n.text("workspaces.waiting"), .waiting)
        var line = L10n.text("workspaces.windows.ready", String(describing: (settledCount)), String(describing: (entries.count)))
        if !problems.isEmpty { line = L10n.text("text.labelValue", line, problems.joined(separator: L10n.text("text.listSeparator"))) }
        return notice.map { L10n.text("text.sentence", line, $0) } ?? line
    }
}
