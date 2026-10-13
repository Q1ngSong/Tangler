import CoreKit
import OverlayKit
import SwiftUI

/// The layout module's page in the settings window.
struct LayoutSettingsView: View {
    @Bindable var model: LayoutSettingsModel

    var body: some View {
        Form {
            Section {
                SettingsFeaturePreview(L10n.text("windowlayout.arrange.windows.on.a.grid"), scene: .layout(columns: model.settings.snapGrid.columns,
                    rows: model.settings.snapGrid.rows, gap: Double(model.settings.gapPoints)),
                    input: .drag(model.settings.gridModifiers))
            }
            Section(L10n.text("windowlayout.dragging.windows")) {
                Toggle(L10n.text("windowlayout.snap.windows.at.screen.edges"), isOn: $model.settings.edgeSnapping)
                Toggle(L10n.text("windowlayout.show.the.grid.when.dragging.with.modifiers"), isOn: $model.settings.grid)
                Picker(L10n.text("windowlayout.grid.modifiers"), selection: $model.settings.gridModifiers) {
                    ForEach(model.modifierChoices) { choice in
                        Text(choice.title).tag(choice.modifiers)
                    }
                }
                .disabled(!model.settings.grid)
                Stepper(L10n.text("windowlayout.grid.columns", String(describing: (model.settings.gridColumns))), value: $model.settings.gridColumns, in: 1...12)
                    .disabled(!model.settings.grid)
                Stepper(L10n.text("windowlayout.grid.rows", String(describing: (model.settings.gridRows))), value: $model.settings.gridRows, in: 1...12)
                    .disabled(!model.settings.grid)
                Toggle(L10n.text("windowlayout.use.glass.for.snap.previews"), isOn: $model.settings.glassSnapPreview)
                Text(L10n.text("windowlayout.with.liquid.glass.appearance.show.the.target"))
                    .font(SettingsTypography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section(L10n.text("windowlayout.placement")) {
                LabeledContent(L10n.text("windowlayout.window.gap.pt", String(describing: (Int(model.settings.gap))))) {
                    Slider(value: $model.settings.gap, in: 0...40, step: 2)
                }
                LabeledContent(L10n.text("windowlayout.animation.duration", String(describing: (Self.duration(model.settings.animationDuration))))) {
                    Slider(value: $model.settings.animationDuration, in: 0...0.5, step: 0.02)
                }
            }
            Section(L10n.text("windowlayout.desktops")) {
                Toggle(L10n.text("windowlayout.let.tangler.handle.desktop.shortcuts"), isOn: $model.settings.handlesDesktopKeys)
                Text(L10n.text("windowlayout.use.and.number.to.switch.desktops.through"))
                    .font(SettingsTypography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L10n.text("windowlayout.disable.system.desktop.shortcuts")) { model.openKeyboardSettings() }
                if model.showsSystemDesktopShortcuts {
                    Text(L10n.text("windowlayout.tangler.does.not.change.system.settings.in")
                         + LayoutSettingsModel.systemDesktopShortcuts.map { "· \($0)" }.joined(separator: "\n"))
                        .font(SettingsTypography.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !model.conflicts.isEmpty {
                Section(L10n.text("windowlayout.system.window.tiling.conflicts")) {
                    ForEach(model.conflicts, id: \.self) { line in
                        Label(line, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                    Text(L10n.text("windowlayout.tangler.does.not.change.system.settings.turn"))
                        .font(SettingsTypography.body)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button(L10n.text("windowlayout.open.desktop.dock.settings")) { model.openSystemSettings() }
                        Button(L10n.text("windowlayout.check.again")) { model.refreshTiling() }
                    }
                }
            }
        }
        .settingsFormStyle()
        .onAppear { model.refreshTiling() }
    }

    private static func duration(_ seconds: Double) -> String {
        seconds <= 0 ? L10n.text("windowlayout.no.animation") : String(format: L10n.text("layout.animation.secondsFormat"), locale: L10n.current.locale, seconds)
    }
}
