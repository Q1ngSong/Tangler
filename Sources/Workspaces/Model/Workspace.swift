import Foundation

/// A named checkpoint (entries and tab groups) and the desktop it owns.
struct Workspace: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var createdAt: Date
    /// The entries; may be empty.
    var windows: [SavedWindow]
    var tabGroups: [SavedTabGroup] = []
    /// When the checkpoint was last saved.
    var savedAt: Date?
    /// Width over height of the visible frame the checkpoint was saved on; the preview's board.
    var screenAspect: Double?
    /// Nil when the workspace was never opened or its desktop is gone.
    var desktop: BoundDesktop?
    /// A template: its checkpoint is only saved when the user asks, never automatically.
    var isLocked = false
    /// When the workspace was deleted; nil unless it is in the recycle bin.
    var deletedAt: Date?
    var options: WorkspaceOptions
}

extension Workspace {
    /// Distinct applications among the entries.
    var appCount: Int { Set(windows.map { $0.bundleID ?? $0.appName }).count }
}

/// What restoring may do besides moving windows that are already open. Both are off by
/// default here, which is what a migrated workspace keeps; the library turns them on for the
/// workspaces it creates.
struct WorkspaceOptions: Codable, Equatable, Sendable {
    /// Launch saved applications that are not running.
    var launchesMissingApps = false
    /// Open the configured document, folder or web page for saved windows without a match.
    var reopensMissingWindows = false
    /// The saved window to focus afterwards; nil leaves the focus alone.
    var focusedWindow: UUID?
}
