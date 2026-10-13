import CoreKit
import CommandKit
import Contracts
import OverlayKit
import SwiftUI

struct SettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        GeometryReader { room in
            let width = SettingsPageLayout.navigationWidth(available: room.size.width)
            let compact = width < 128
            HStack(spacing: 0) {
                sidebar(compact: compact)
                    .frame(width: width)
                    .background { SettingsSidebarBackground() }
                Group {
                    switch model.page {
                    case .general: GeneralPage(model: model)
                    case .shortcuts: ShortcutsPage(model: model)
                    case .diagnostics: DiagnosticsPage(model: model)
                    case .module(let id): ModulePage(model: model, id: id)
                    }
                }
                .settingsPageTitle(pageTitle)
                .environment(\.settingsCompactLayout, room.size.width - width < 600)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .settingsColumnTransition(compact: compact)
            .clipShape(RoundedRectangle(cornerRadius: SettingsPageLayout.windowCornerRadius, style: .continuous))
        }
        .padding(SettingsPageLayout.windowOuterInset)
        .frame(minWidth: SettingsWindowController.minimumContentSize.width,
               minHeight: SettingsWindowController.minimumContentSize.height)
        .ignoresSafeArea(.container, edges: .top)
        .environment(\.locale, L10n.current.locale)
        .environment(\.skin, model.appSettings.skin)
        .environment(\.settingsInputBindings, model.previewInputBindings)
    }

    private func sidebar(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: compact ? 0 : 7) {
                TanglerMark().frame(width: 20, height: 20)
                Text("Tangler").font(SettingsTypography.brand).lineLimit(1).fixedSize()
                    .frame(width: compact ? 0 : nil, alignment: .leading)
                    .opacity(compact ? 0 : 1).clipped().accessibilityHidden(compact)
            }
                .foregroundStyle(.primary.opacity(0.75))
                .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
                .padding(.leading, compact ? 0 : 22)
                .padding(.top, 60).padding(.bottom, 19)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Tangler")
            List(selection: $model.page) {
                navigationRow(L10n.text("app.general"), symbol: "gearshape", page: .general, compact: compact)
                navigationRow(L10n.text("app.shortcuts"), symbol: "keyboard", page: .shortcuts, compact: compact)
                navigationGroup(L10n.text("app.modules"), compact: compact)
                ForEach(FeatureCatalog.names, id: \.id) { module in
                    navigationRow(module.name, symbol: FeatureCatalog.symbol(for: module.id),
                                  page: .module(module.id), compact: compact)
                }
                navigationGroup(L10n.text("app.support"), compact: compact)
                navigationRow(L10n.text("app.diagnostics"), symbol: "waveform.path.ecg", page: .diagnostics, compact: compact)
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 1)
            .contentMargins(0, for: .scrollContent)
            .scrollContentBackground(.hidden)
        }
    }

    private var pageTitle: String {
        switch model.page {
        case .general: L10n.text("app.general")
        case .shortcuts: L10n.text("app.shortcuts")
        case .diagnostics: L10n.text("app.diagnostics")
        case .module(let id): FeatureCatalog.names.first { $0.id == id }?.name ?? L10n.text("app.modules")
        }
    }

    private func navigationRow(_ title: String, symbol: String, page: SettingsPage, compact: Bool) -> some View {
        HStack(spacing: compact ? 0 : 10) {
            Image(systemName: symbol).font(.system(size: 17)).frame(width: 17)
            Text(title).lineLimit(1).fixedSize()
                .frame(width: compact ? 0 : nil, alignment: .leading)
                .opacity(compact ? 0 : 1).clipped().accessibilityHidden(compact)
        }
        .settingsSidebarRow(selected: model.page == page, compact: compact)
        .padding(.bottom, 3)
        .tag(page).help(title).accessibilityLabel(title)
        // The plain macOS List adds 8 pt, giving the prototype's 12 pt outer inset.
        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func navigationGroup(_ title: String, compact: Bool) -> some View {
        Text(title)
            .font(SettingsTypography.sidebarSection)
            .foregroundStyle(.secondary)
            .padding(.horizontal, compact ? 0 : 15).padding(.top, 20).padding(.bottom, 7)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .selectionDisabled()
            .opacity(compact ? 0 : 1)
            .accessibilityHidden(compact)
            .accessibilityAddTraits(.isHeader)
    }

}

private struct GeneralPage: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section(L10n.text("app.appearance")) {
                HStack(spacing: 16) {
                    ForEach(Skin.allCases, id: \.self) { skin in
                        Button { model.setSkin(skin) } label: {
                            VStack(spacing: 12) {
                                SettingsAppearanceSample(skin: skin)
                                    .overlay(RoundedRectangle(cornerRadius: 17)
                                        .strokeBorder(model.appSettings.skin == skin ? Color.accentColor : .clear, lineWidth: 2)
                                        .padding(-4))
                                HStack(spacing: 7) {
                                    Text(skin.title).fontWeight(.medium)
                                    Image(systemName: model.appSettings.skin == skin ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(model.appSettings.skin == skin ? Color.accentColor : Color.secondary)
                                }
                            }
                            .padding(8)
                            .contentShape(RoundedRectangle(cornerRadius: 20))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(skin.title)
                        .accessibilityAddTraits(model.appSettings.skin == skin ? .isSelected : [])
                    }
                }
                .frame(maxWidth: 540)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            Section(L10n.text("settings.preferences")) {
                Picker(selection: Binding(get: { model.appSettings.language }, set: model.setLanguage)) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.title).tag(language)
                    }
                } label: {
                    SettingsControlLabel(L10n.text("settings.language.interface"), detail: L10n.text("settings.language.immediate"))
                }
                Toggle(L10n.text("app.launch.tangler.at.login"), isOn: Binding(get: { model.launchAtLogin }, set: model.setLaunchAtLogin))
                if let problem = model.launchAtLoginProblem { Text(problem).font(SettingsTypography.caption).foregroundStyle(.red) }
            }
            Section {
                ForEach(FeatureCatalog.names, id: \.id) { module in
                    Toggle(isOn: Binding(get: { model.appSettings.isEnabled(module.id) },
                                         set: { model.setModule(module.id, enabled: $0) })) {
                        Label {
                            Text(module.name)
                        } icon: {
                            Image(systemName: FeatureCatalog.symbol(for: module.id))
                                .foregroundStyle(.secondary).frame(width: 18)
                        }
                    }
                }
            } header: {
                Text(L10n.text("app.modules"))
            } footer: {
                Text(L10n.text("app.restart.tangler.to.apply.changes.to.enabled"))
            }
        }
        .settingsFormStyle()
        .onAppear { model.refresh() }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let request: () -> Void
    let open: () -> Void
    @Environment(\.settingsCompactLayout) private var compact

    var body: some View {
        (compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 16))) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(granted ? .green : .orange).padding(.top, 3)
                SettingsControlLabel(title, detail: detail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !granted {
                HStack {
                    Button(L10n.text("app.request.access"), action: request)
                    Button(action: open) { Image(systemName: "arrow.up.right.square") }
                        .help(L10n.text("app.open.system.settings"))
                        .accessibilityLabel(L10n.text("app.open.system.settings"))
                }.fixedSize()
            }
        }
    }
}

private struct ModulePage: View {
    let model: SettingsModel
    let id: ModuleID

    var body: some View {
        if let view = model.settingsView(for: id) {
            view
        } else {
            SettingsPageTemplate {
                ModulePlaceholder(message: model.isRunning(id) ? L10n.text("app.this.module.has.no.settings")
                                  : model.accessibilityGranted ? L10n.text("app.this.module.is.not.running.enable.it")
                                  : L10n.text("app.grant.accessibility.access.in.diagnostics.to.start"),
                                  id: id)
                    .padding(SettingsPageLayout.contentInset)
            }
        }
    }
}

private struct DiagnosticsPage: View {
    let model: SettingsModel

    var body: some View {
        ScrollViewReader { scroll in
            Form {
                if !model.failures.isEmpty {
                    Section(L10n.text("app.needs.attention")) {
                        ForEach(model.failures.sorted(by: { $0.key.rawValue < $1.key.rawValue }), id: \.key) { failure in
                            Label(L10n.text("text.labelValue", failure.key.rawValue, failure.value), systemImage: "exclamationmark.triangle")
                                .font(SettingsTypography.body).foregroundStyle(.orange)
                        }
                    }
                }
                if let updates = model.updates {
                    UpdateSettingsSection(updates: updates, onShowPermissions: { scroll.scrollTo("permissions", anchor: .top) })
                }
                Section {
                    PermissionRow(title: L10n.text("app.accessibility"), detail: L10n.text("app.move.windows.list.windows.and.handle.global"), granted: model.accessibilityGranted,
                                  request: model.requestAccessibility, open: { Permissions.open(.accessibility) })
                    PermissionRow(title: L10n.text("app.screen.recording"), detail: L10n.text("app.window.thumbnails.in.the.switcher.and.dock"), granted: model.screenRecordingGranted,
                                  request: model.requestScreenRecording, open: { Permissions.open(.screenRecording) })
                    if !model.accessibilityGranted {
                        DisclosureGroup(L10n.text("app.access.granted.but.still.not.working")) {
                            Text(L10n.text("app.macos.may.retain.a.signature.record.from"))
                                .font(SettingsTypography.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(L10n.text("app.permissions"))
                } footer: {
                    Text(L10n.text("app.tangler.detects.newly.granted.access.automatically.screen"))
                }.id("permissions")
                Section {
                    DisclosureGroup(L10n.text("app.system.capabilities")) {
                        ForEach(model.capabilityStatuses, id: \.name) { status in
                            if let reason = status.reason {
                                DisclosureGroup {
                                    Text(reason).font(SettingsTypography.caption).foregroundStyle(.secondary)
                                } label: {
                                    capabilityLabel(status.name, available: status.isAvailable)
                                }
                            } else {
                                capabilityLabel(status.name, available: status.isAvailable)
                            }
                        }
                    }
                }
                if model.updates == nil { Section(L10n.text("app.version")) { Text("Tangler \(TanglerMain.version)") } }
            }
            .settingsFormStyle()
            .onAppear { model.refresh(loginItem: false) }
        }
    }

    private func capabilityLabel(_ title: String, available: Bool) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: available ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(available ? .green : .orange)
        }
    }
}
