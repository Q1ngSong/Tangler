import CoreKit
import Contracts
import OverlayKit
import SwiftUI

/// The entry-key controls share the shortcut page's card and confirmed recorder.
public struct LeaderTriggerSettingsSection: View {
    private let store: any SettingsStore
    private let input: any InputService
    private let commands: [CommandSpec]
    private let onTriggerChange: ((LeaderTrigger) -> Void)?
    @State private var form: LeaderTriggerForm
    @Environment(\.settingsCompactLayout) private var compact

    public init(store: any SettingsStore, input: any InputService, commands: [CommandSpec],
                onTriggerChange: ((LeaderTrigger) -> Void)? = nil) {
        self.store = store
        self.input = input
        self.commands = commands
        self.onTriggerChange = onTriggerChange
        _form = State(initialValue: LeaderTriggerForm(store.load(PaletteSettings.self).leaderTrigger))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.text("commandpalette.leader.key")).font(SettingsTypography.sectionTitle)
                Spacer(minLength: 8)
                Picker(L10n.text("commandpalette.trigger"), selection: $form.choice) {
                    Text(L10n.text("commandpalette.right.command")).tag(LeaderTriggerForm.Choice.rightCommand)
                    Text(L10n.text("commandpalette.key.combination")).tag(LeaderTriggerForm.Choice.chord)
                }
                .pickerStyle(.radioGroup).horizontalRadioGroupLayout().labelsHidden()
                .font(SettingsTypography.caption)
            }
            HStack(spacing: 12) {
                Text(ShortcutKeySymbols.label(form.trigger))
                    .font(SettingsTypography.body)
                    .padding(.horizontal, 8).frame(minWidth: 46, minHeight: 36)
                    .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
                VStack(alignment: .leading, spacing: 4) {
                    Text(form.choice == .rightCommand && form.holds ? L10n.text("commandpalette.hold.the.leader.key.then.enter.the") : L10n.text("commandpalette.press.the.leader.key.then.enter.the"))
                        .font(SettingsTypography.body.weight(.medium))
                    note(L10n.text("commandpalette.global.shortcuts.work.without.the.leader.key"))
                }
            }
            if form.choice == .rightCommand {
                HStack(alignment: .top, spacing: 10) {
                    Toggle(L10n.text("commandpalette.hold.to.enter.keys"), isOn: $form.holds).toggleStyle(.checkbox).fixedSize()
                    note(form.holds ? L10n.text("commandpalette.use.left.command.for.regular.shortcuts.while") : L10n.text("commandpalette.press.and.release.right.command.then.enter"))
                }.font(SettingsTypography.caption)
            } else {
                ShortcutRecorder(chord: $form.chord, placeholder: L10n.text("commandpalette.record.combination"), showsKeySymbols: true,
                                 style: .confirmed(previewWidth: compact ? 126 : 174),
                                 onRecordingChange: { input.setShortcutsSuspended($0) })
                if form.chord == nil { note(L10n.text("commandpalette.no.combination.is.set.right.command.is")) }
                if let clash = form.clash(in: commands) {
                    note(L10n.text("commandpalette.uses.this.combination.too.setting.it.as", String(describing: (clash.title))), isWarning: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsGroupSurface()
        .onAppear { onTriggerChange?(form.trigger) }
        .onChange(of: form) { _, _ in
            var settings = store.load(PaletteSettings.self)
            settings.leaderTrigger = form.trigger
            store.save(settings)
            onTriggerChange?(form.trigger)
        }
    }

    private func note(_ text: String, isWarning: Bool = false) -> some View {
        Text(text)
            .font(SettingsTypography.caption)
            .foregroundStyle(isWarning ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            .fixedSize(horizontal: false, vertical: true)
    }
}
