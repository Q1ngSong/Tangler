import Foundation
import Observation

/// Ephemeral settings navigation: each list keeps its own selection when the bin is toggled.
@MainActor @Observable
final class WorkspaceSettingsNavigation {
    private(set) var showsBin = false
    var workspaceSelection: UUID?
    var binSelection: UUID?

    var selection: UUID? {
        get { showsBin ? binSelection : workspaceSelection }
        set {
            if showsBin { binSelection = newValue }
            else { workspaceSelection = newValue }
        }
    }

    func toggle(workspaces: [Workspace], bin: [Workspace]) {
        reconcile(workspaces: workspaces, bin: bin)
        showsBin.toggle()
    }

    /// Restores and expiry can remove the selected row while either list is hidden.
    func reconcile(workspaces: [Workspace], bin: [Workspace]) {
        if !workspaces.contains(where: { $0.id == workspaceSelection }) { workspaceSelection = workspaces.first?.id }
        if !bin.contains(where: { $0.id == binSelection }) { binSelection = bin.first?.id }
    }
}
