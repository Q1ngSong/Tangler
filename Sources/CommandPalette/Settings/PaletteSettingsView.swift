import CoreKit
import Contracts
import OverlayKit
import SwiftUI

/// Search preview and command linger timing. The leader trigger lives on the Shortcuts page.
struct PaletteSettingsView: View {
    private let store: any SettingsStore
    @State private var lingerSeconds: Double

    init(store: any SettingsStore) {
        self.store = store
        let settings = store.load(PaletteSettings.self)
        _lingerSeconds = State(initialValue: settings.lingerSeconds)
    }

    var body: some View {
        Form {
            Section {
                SettingsFeaturePreview(L10n.text("commandpalette.open.command.search"), scene: .palette, input: .command("palette.open"))
                Text(L10n.text("commandpalette.find.and.run.commands.and.quickly.locate")).font(SettingsTypography.caption).foregroundStyle(.secondary)
            }
            Section(L10n.text("commandpalette.linger")) {
                LabeledContent(L10n.text("commandpalette.stay.after.a.layout.command")) {
                    HStack {
                        Slider(value: $lingerSeconds, in: 0.5...3, step: 0.25).frame(width: 160)
                        Text(L10n.text("commandpalette.s", String(describing: (lingerSeconds.formatted(.number.precision(.fractionLength(0...2))))))).monospacedDigit()
                    }
                }
                note(L10n.text("commandpalette.while.lingering.repeat.the.same.key.to"))
            }
        }
        .settingsFormStyle()
        .onChange(of: lingerSeconds) { _, _ in save() }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(SettingsTypography.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func save() {
        var settings = store.load(PaletteSettings.self)
        settings.lingerSeconds = lingerSeconds
        store.save(settings)
    }
}
