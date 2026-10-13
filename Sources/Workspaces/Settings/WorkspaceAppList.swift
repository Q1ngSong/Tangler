import CoreKit
import OverlayKit
import SwiftUI

/// Checkpoint entries grouped by application; an optional edit action enables the row buttons.
struct WorkspaceAppList: View {
    let workspace: Workspace
    var edit: ((SavedWindow) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("workspaces.apps.and.windows")).font(SettingsTypography.sectionTitle)
            ForEach(EntrySummary.rows(for: workspace)) { row in
                if let edit {
                    Button { edit(row.entry) } label: { entryRow(row) }.buttonStyle(.plain)
                } else {
                    entryRow(row)
                }
                Divider()
            }
        }
    }

    private func entryRow(_ row: EntrySummary.Row) -> some View {
        HStack(spacing: 8) {
            WorkspacePreview.icon(for: row.entry).resizable().scaledToFit().frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).lineLimit(1)
                Text(row.caption).font(SettingsTypography.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if edit != nil {
                Image(systemName: "chevron.right").font(SettingsTypography.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
