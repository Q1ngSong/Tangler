import CoreKit
import OverlayKit
import Contracts
import SwiftUI

/// The switcher's settings page. Changes are saved at once and apply to the next switcher.
struct SwitcherSettingsView: View {
    let store: any SettingsStore
    /// Warnings and explanations, e.g. that the system switcher may still appear.
    let notes: [String]
    @State private var settings: SwitcherSettings

    init(store: any SettingsStore, notes: [String]) {
        self.store = store
        self.notes = notes
        _settings = State(initialValue: store.load(SwitcherSettings.self))
    }

    var body: some View {
        Form {
            Section {
                SettingsFeaturePreview(L10n.text("switcher.switch.windows"), scene: .switcher(height: settings.effectivePreviewHeight),
                    input: .command("switcher.allWindows"))
            }
            Section {
                Toggle(L10n.text("switcher.include.minimized.windows"), isOn: binding(\.includeMinimized))
                LabeledContent(L10n.text("switcher.thumbnail.height")) {
                    HStack {
                        Slider(value: binding(\.previewHeight), in: SwitcherSettings.previewHeightRange, step: 10)
                        Text(L10n.text("switcher.pt", String(describing: (Int(settings.effectivePreviewHeight)))))
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            }
            if !notes.isEmpty {
                Section(L10n.text("switcher.notes")) {
                    ForEach(notes, id: \.self) { note in
                        Label(note, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .settingsFormStyle()
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<SwitcherSettings, Value>) -> Binding<Value> {
        Binding(get: { settings[keyPath: keyPath] }, set: { value in
            settings[keyPath: keyPath] = value
            store.save(settings)
        })
    }
}
