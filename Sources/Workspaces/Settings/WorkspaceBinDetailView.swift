import CoreKit
import OverlayKit
import SwiftUI

/// Deleted checkpoints reuse the workspace preview and app rows, without editable or launch actions.
struct WorkspaceBinDetailView: View {
    let workspace: Workspace
    let daysLeft: Int
    let restore: () -> Void
    let purge: () -> Void
    @Environment(\.settingsCompactLayout) private var compact

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(workspace.name).font(SettingsTypography.sectionTitle).lineLimit(1)
                Text(L10n.count("workspaces.in.trash.days.remaining", daysLeft)).font(SettingsTypography.caption).foregroundStyle(.secondary)
                HStack {
                    Button(L10n.text("workspaces.restore"), systemImage: "arrow.uturn.backward", action: restore).buttonStyle(.borderedProminent)
                    Button(L10n.text("workspaces.delete.permanently"), role: .destructive, action: purge)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if workspace.windows.isEmpty {
                        EmptyState(L10n.text("workspaces.no.saved.windows"), systemImage: "macwindow")
                    } else {
                        SettingsPreview(L10n.text("workspaces.restore.workspace"), aspectRatio: 16.0 / 10, maxWidth: 480) {
                            WorkspacePreview(workspace: workspace, fallbackAspect: 1.6, height: nil)
                                .padding(16)
                                .allowsHitTesting(false)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(L10n.text("workspaces.window.layout.of.the.deleted.workspace"))
                        }
                        Text(EntrySummary.checkpointLine(for: workspace)).font(SettingsTypography.caption).foregroundStyle(.secondary)
                        WorkspaceAppList(workspace: workspace)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(compact ? 12 : SettingsPageLayout.contentInset)
    }
}
