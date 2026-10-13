import CoreKit
import OverlayKit
import Contracts
import SwiftUI

/// The module's settings page. Every change is saved at once; the module picks it up live.
struct DockPreviewSettingsView: View {
    private let store: any SettingsStore
    private let windows: any WindowService
    private var limitation: String? { Self.limitation(for: windows) }
    @State private var settings: DockPreviewSettings

    init(store: any SettingsStore, windows: any WindowService) {
        self.store = store
        self.windows = windows
        var settings = store.load(DockPreviewSettings.self)
        settings.showDelay = settings.effectiveShowDelay
        settings.dismissDelay = settings.effectiveDismissDelay
        _settings = State(initialValue: settings)
    }

    var body: some View {
        Form {
            Section {
                SettingsFeaturePreview(L10n.text("dockpreview.hover.to.preview.application.windows"), scene: .dock(enabled: settings.previewsEnabled),
                    input: .gesture(symbol: "cursorarrow", label: L10n.text("dockpreview.hover")))
            }
            Section {
                Toggle(L10n.text("dockpreview.preview.windows.when.hovering.over.a.dock"), isOn: $settings.previewsEnabled)
                Group {
                    Toggle(L10n.text("dockpreview.preview.apps.with.only.one.window"), isOn: $settings.showsSingleWindowApps)
                    delay(L10n.text("dockpreview.show.delay"), value: $settings.showDelay, in: DockPreviewSettings.showDelayRange)
                    delay(L10n.text("dockpreview.hide.delay"), value: $settings.dismissDelay, in: DockPreviewSettings.dismissDelayRange)
                    Toggle(L10n.text("dockpreview.animate.previews"), isOn: $settings.animates)
                    Text(L10n.text("dockpreview.fade.in.and.slide.gently.from.the"))
                        .font(SettingsTypography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle(L10n.text("dockpreview.hide.dock.icon.labels"), isOn: $settings.hidesDockHover)
                    Text(hoverNote)
                        .font(SettingsTypography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .disabled(!settings.previewsEnabled)
            } header: {
                Text(L10n.text("dockpreview.hover.previews"))
            } footer: {
                if let limitation { Text(limitation) }
            }
            Section {
                Picker(L10n.text("dockpreview.click.behavior"), selection: $settings.clickBehavior) {
                    ForEach(DockClickBehavior.allCases, id: \.self) { behavior in
                        Text(behavior.title).tag(behavior)
                    }
                }
            } header: {
                Text(L10n.text("dockpreview.clicking.a.dock.icon"))
            } footer: {
                Text(L10n.text("dockpreview.applies.only.to.the.frontmost.app.s"))
            }
        }
        .settingsFormStyle()
        .onChange(of: settings) { _, newValue in store.save(newValue) }
    }

    /// What hiding the Dock's names costs, and when it cannot work.
    private var hoverNote: String {
        if DockPreferences.autohides() {
            return L10n.text("dockpreview.unavailable.when.the.dock.hides.automatically.pointer")
        }
        return L10n.text("dockpreview.tangler.intercepts.pointer.movement.over.dock.icons")
    }

    /// Why the preview leaves out windows on other desktops, when it does.
    static func limitation(for windows: any WindowService) -> String? {
        windows.unavailableReason(for: .otherSpaceWindows).map { L10n.text("dockpreview.windows.on.other.desktops.are.excluded", String(describing: ($0))) }
    }

    private func delay(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range, step: 0.05)
                Text(L10n.text("commandpalette.s", value.wrappedValue.formatted(.number.precision(.fractionLength(2)).locale(L10n.current.locale))))
                    .monospacedDigit()
                    .frame(width: 56, alignment: .trailing)
            }
        }
    }
}
