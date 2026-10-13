import CoreKit
import OverlayKit
import SwiftUI

struct UpdateSettingsSection: View {
    let updates: AppUpdates

    var body: some View {
        Section(L10n.text("app.software.updates")) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    version
                    Spacer(minLength: 8)
                    checkButton
                }
                VStack(alignment: .leading, spacing: 10) {
                    version
                    checkButton
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Picker(L10n.text("app.update.policy"), selection: Binding(get: { updates.updateMode }, set: updates.setUpdateMode)) {
                    ForEach(AppUpdateMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .disabled(!updates.isConfigured || updates.startupProblem != nil)
                Text(updates.isConfigured ? updates.updateMode.detail : L10n.text("app.online.updates.are.not.configured.in.this"))
                    .font(SettingsTypography.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let problem = updates.startupProblem {
                Text(problem).font(SettingsTypography.caption).foregroundStyle(.red)
            }
        }
    }

    private var version: some View {
        VStack(alignment: .leading, spacing: 6) {
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
