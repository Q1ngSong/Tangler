import CoreKit
import OverlayKit
import SwiftUI

struct UpdateSettingsSection: View {
    let updates: AppUpdates
    var onShowPermissions: (() -> Void)? = nil

    var body: some View {
        Section(L10n.text("app.software.updates")) {
            SettingsPreview(L10n.text("settings.preview.health.title"), maxWidth: 560) {
                VStack(spacing: 10) {
                    TanglerMark().frame(width: 34, height: 34)
                    version
                    if updates.checkStatus == .checking { ProgressView().controlSize(.small) }
                }
                .multilineTextAlignment(.center)
                .padding(16).frame(maxWidth: 310)
                .settingsPreviewSurface(cornerRadius: 22)
                .padding(.horizontal, 16)
            }
            HStack(spacing: 8) {
                checkButton
                if let onShowPermissions {
                    Button(L10n.text("settings.preview.health.permissions"), action: onShowPermissions)
                }
            }
            Picker(selection: Binding(get: { updates.updateMode }, set: updates.setUpdateMode)) {
                ForEach(AppUpdateMode.allCases) { mode in Text(mode.title).tag(mode) }
            } label: {
                SettingsControlLabel(L10n.text("app.update.policy"), detail:
                    updates.isConfigured ? updates.updateMode.detail : L10n.text("app.online.updates.are.not.configured.in.this"))
            }
            .disabled(!updates.isConfigured || updates.startupProblem != nil)
            if let problem = updates.startupProblem {
                Text(problem).font(SettingsTypography.caption).foregroundStyle(.red)
            }
        }
    }

    private var version: some View {
        VStack(spacing: 6) {
            Text("Tangler \(TanglerMain.version)").fontWeight(.medium)
            if updates.isConfigured {
                Text(updates.checkStatus.message)
                    .font(SettingsTypography.caption)
                    .foregroundStyle(updates.checkStatus.isFailure ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let date = updates.lastUpdateCheckDate {
                    Text(L10n.text("app.last.checked", String(describing: (date.formatted(.dateTime.year().month().day().hour().minute().locale(L10n.current.locale))))))
                        .font(SettingsTypography.caption).foregroundStyle(.secondary)
                } else {
                    Text(L10n.text("app.not.checked.yet")).font(SettingsTypography.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var checkButton: some View {
        Button(updates.checkStatus == .checking ? L10n.text("app.checking") : L10n.text("app.check.for.updates"), action: updates.checkForUpdates)
            .disabled(!updates.canCheckForUpdates)
            .fixedSize()
    }
}
