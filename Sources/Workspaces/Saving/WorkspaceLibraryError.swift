import CoreKit
/// Why a change to the saved workspaces was refused.
enum WorkspaceLibraryError: Error, Equatable {
    case noWindows
    case emptyName
    case missingWorkspace
    case missingEntry
    case invalidReopen(String)
    /// The system gives the desktop no UUID.
    case unnamedDesktop

    var message: String {
        switch self {
        case .noWindows: return L10n.text("workspaces.there.are.no.windows.to.save")
        case .emptyName: return L10n.text("workspaces.a.workspace.name.cannot.be.empty")
        case .missingWorkspace: return L10n.text("workspaces.this.workspace.no.longer.exists")
        case .missingEntry: return L10n.text("workspaces.this.entry.no.longer.exists")
        case .invalidReopen(let reason): return reason
        case .unnamedDesktop: return L10n.text("workspaces.the.system.did.not.identify.this.desktop")
        }
    }
}
