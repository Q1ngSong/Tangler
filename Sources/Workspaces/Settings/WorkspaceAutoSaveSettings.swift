import CoreKit
import OverlayKit
import SwiftUI

/// The page's compact options popover, using the existing automatic-save settings and scheduler.
struct WorkspaceAutoSaveSettings: View {
    let controller: WorkspacesController
    private var library: WorkspaceLibrary { controller.library }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("workspaces.workspace.settings")).font(SettingsTypography.sectionTitle).accessibilityAddTraits(.isHeader)
            Divider()
            Toggle(L10n.text("workspaces.autosave"), isOn: Binding(get: { library.autoSave }, set: { controller.setAutoSave($0) }))
                .toggleStyle(.switch).controlSize(.small)
            Stepper(L10n.count("workspaces.every.minutes", library.autoSaveMinutes),
                    value: Binding(get: { library.autoSaveMinutes }, set: { controller.setAutoSaveMinutes($0) }),
                    in: WorkspaceSettings.autoSaveMinutesRange)
                .disabled(!library.autoSave)
                .accessibilityLabel(L10n.text("workspaces.autosave.interval"))
                .accessibilityValue(L10n.count("workspaces.minutes", library.autoSaveMinutes))
            Text(L10n.text("workspaces.locked.templates.are.saved.manually.only.empty"))
                .font(SettingsTypography.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(SettingsTypography.body)
        .padding(16).frame(width: 280)
        .help(L10n.text("workspaces.save.the.current.workspace.periodically.and.when"))
    }
}
