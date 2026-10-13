import CoreKit
import OverlayKit
import Contracts
import SwiftUI

/// The module's settings page. Preview changes are immediate; the model delays height saves.
struct TabGroupsSettingsView: View {
    /// Each command's name and its keys after the leader trigger, with the user's overrides.
    private let keys: [(title: String, keys: String)]
    @State private var model: TabGroupsSettingsModel

    init(store: any SettingsStore, commands: [CommandSpec]) {
        keys = commands.map { spec in (title: spec.title, keys: spec.leaderKeys.map(\.description).joined(separator: " / ")) }
        _model = State(initialValue: TabGroupsSettingsModel(store: store))
    }

    var body: some View {
        Form {
            Section {
                SettingsFeaturePreview(L10n.text("settings.preview.tabs.title"),
                    scene: .tabs(height: model.settings.barHeight, joining: false))
                SettingsSlider(L10n.text("tabgroups.height"), value: $model.settings.barHeight,
                    in: TabGroupsSettings.barHeightRange, step: 2,
                    formattedValue: L10n.text("switcher.pt", String(Int(model.settings.barHeight))))
            } footer: {
                Text(L10n.text("tabgroups.clicking.a.tab.brings.only.that.window"))
            }
            Section {
                Toggle(isOn: $model.settings.mergesOnSnap) {
                    SettingsControlLabel(L10n.text("tabgroups.group.windows.snapped.to.the.same.area"),
                        detail: L10n.text("tabgroups.when.a.window.settles.into.the.exact"))
                }
                Toggle(isOn: $model.settings.joinsByCommandDrag) {
                    SettingsControlLabel(L10n.text("tabgroups.hold.and.drag.a.window.onto.a"),
                        detail: L10n.text("tabgroups.hold.before.dragging.to.detach.a.window"))
                }
            } header: {
                Text(L10n.text("tabgroups.grouping"))
            }
            Section {
                ForEach(keys, id: \.title) { entry in
                    LabeledContent(entry.title, value: entry.keys)
                }
            } header: {
                Text(L10n.text("tabgroups.keys.after.the.leader.key"))
            }
        }
        .settingsFormStyle()
        .onDisappear { model.flush() }
    }

}
