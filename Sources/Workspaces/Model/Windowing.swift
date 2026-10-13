import CoreKit
import Contracts

/// How an entry gets its window when the workspace is expanded (design 5.3).
enum Windowing: String, Codable, CaseIterable, Identifiable, Sendable {
    /// A new window when the entry has contents or the application offers "new window";
    /// otherwise the application's only window.
    case automatic
    case newWindow
    case onlyWindow

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: return L10n.text("workspaces.automatic")
        case .newWindow: return L10n.text("workspaces.open.a.new.window")
        case .onlyWindow: return L10n.text("workspaces.use.its.only.window")
        }
    }
}

/// A window as the system numbers it. Both parts change when the application quits, so
/// together they name the window only while it stays open.
struct WindowRef: Codable, Hashable, Sendable {
    var windowID: WindowID
    var pid: Int32
}
