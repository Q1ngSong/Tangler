import CoreKit
import OverlayKit
import Contracts
import SwiftUI

/// The module's settings page. Preview changes are immediate; the model delays height saves.
struct TabGroupsSettingsView: View {
    /// Each command's name and its keys after the leader trigger, with the user's overrides.
    private let keys: [(title: String, keys: String)]
    @State private var joiningPreview = false
    @State private var model: TabGroupsSettingsModel

    init(store: any SettingsStore, commands: [CommandSpec]) {
        keys = commands.map { spec in (title: spec.title, keys: spec.leaderKeys.map(\.description).joined(separator: " / ")) }
        _model = State(initialValue: TabGroupsSettingsModel(store: store))
    }

    var body: some View {
        Form {
            Section {
                Picker(L10n.text("app.function"), selection: $joiningPreview) {
                    Text(L10n.text("tabgroups.adjust.tab.bar.height")).tag(false)
                    Text(L10n.text("tabgroups.add.any.window.to.a.tab.group")).tag(true)
                }.pickerStyle(.segmented).labelsHidden()
                SettingsFeaturePreview(joiningPreview ? L10n.text("tabgroups.add.any.window.to.a.tab.group") : L10n.text("tabgroups.adjust.tab.bar.height"),
                    scene: .tabs(height: model.settings.barHeight, joining: joiningPreview),
                    input: joiningPreview ? .command("tabs.addWindow")
                        : .gesture(symbol: "slider.horizontal.3", label: L10n.text("tabgroups.adjust.tab.bar.height")))
            }
            Section {
                Toggle(L10n.text("tabgroups.group.windows.snapped.to.the.same.area"), isOn: $model.settings.mergesOnSnap)
                note(L10n.text("tabgroups.when.a.window.settles.into.the.exact"))
                Toggle(L10n.text("tabgroups.hold.and.drag.a.window.onto.a"), isOn: $model.settings.joinsByCommandDrag)
                note(L10n.text("tabgroups.hold.before.dragging.to.detach.a.window"))
            } header: {
                Text(L10n.text("tabgroups.grouping"))
            }
            Section {
                LabeledContent(L10n.text("tabgroups.height")) {
                    HStack {
                        Slider(value: $model.settings.barHeight, in: TabGroupsSettings.barHeightRange, step: 2)
                        Text(L10n.text("switcher.pt", String(describing: (Int(model.settings.barHeight))))).monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
            } header: {
                Text(L10n.text("tabgroups.tab.bar"))
            } footer: {
                Text(L10n.text("tabgroups.clicking.a.tab.brings.only.that.window"))
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

    private func note(_ text: String) -> some View {
        Text(text).font(SettingsTypography.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
