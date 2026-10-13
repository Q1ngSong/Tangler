import CoreKit
import AppKit
import Contracts
import SwiftUI

/// Records a `KeyChord` on a settings page: click, then press the combination. Esc keeps the
/// current chord and Delete removes it. Chords need ⌘, ⌥ or ⌃.
///
/// Keys reach the recorder only after Tangler's global event tap and the system, so a chord
/// that is already a global shortcut never arrives; `onRecordingChange` lets the owner pause
/// those shortcuts while recording.
public struct ShortcutRecorder: View {
    public enum Style {
        case immediate
        /// The preview and action occupy separate columns; a valid key stays a draft until Save.
        case confirmed(previewWidth: CGFloat)
    }

    public static let actionWidth: CGFloat = 52
    public static let columnSpacing: CGFloat = 8
    @Binding private var chord: KeyChord?
    private let placeholder: String
    private let showsKeySymbols: Bool
    private let onRecordingChange: ((Bool) -> Void)?
    private let style: Style
    private let fallbackLabel: String
    private let validate: ((KeyChord?) -> String?)?
    @State private var session = ShortcutRecorderSession()

    public init(chord: Binding<KeyChord?>, placeholder: String = L10n.text("overlaykit.record.shortcut"),
                showsKeySymbols: Bool = false, style: Style = .immediate,
                fallbackLabel: String = "—", validate: ((KeyChord?) -> String?)? = nil,
                onRecordingChange: ((Bool) -> Void)? = nil) {
        _chord = chord
        self.placeholder = placeholder
        self.showsKeySymbols = showsKeySymbols
        self.onRecordingChange = onRecordingChange
        self.style = style
        self.fallbackLabel = fallbackLabel
        self.validate = validate
    }

    public var body: some View {
        Group {
            switch style {
            case .immediate:
                if showsKeySymbols { control.buttonStyle(ShortcutKeycapButtonStyle()) }
                else { control }
            case .confirmed(let width): confirmedControl(previewWidth: width)
            }
        }
        .onDisappear { session.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in session.stop() }
    }

    private var control: some View {
        Button(action: toggle) {
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(session.problem == nil ? Color.primary : Color.red)
                .lineLimit(1)
                .frame(minWidth: 110)
        }
        .help(session.isRecording ? L10n.text("overlaykit.press.a.key.combination.esc.cancels.delete") : L10n.text("overlaykit.click.then.press.a.new.key.combination"))
        .accessibilityLabel(L10n.text("app.shortcuts"))
        .accessibilityValue(session.label(for: chord, placeholder: placeholder))
    }

    private func confirmedControl(previewWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: Self.columnSpacing) {
                Text(session.isRecording ? session.label(for: chord, placeholder: placeholder)
                     : chord.map(ShortcutKeySymbols.label) ?? fallbackLabel)
                    .font(SettingsTypography.body)
                    .foregroundStyle(session.problem != nil ? Color.red : session.isRecording ? .accentColor : .primary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
                    .frame(width: previewWidth, alignment: .trailing)
                    .frame(minHeight: 32)
                    .background(session.isRecording ? Color.accentColor.opacity(0.05) : .clear,
                                in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(session.isRecording ? Color.accentColor.opacity(0.4) : .clear, lineWidth: 1))
                    .accessibilityLabel(L10n.text("app.command"))
                Button(session.isRecording ? L10n.text("overlaykit.save") : L10n.text("overlaykit.record")) {
                    if session.isRecording { session.save() } else { toggle() }
                }
                .buttonStyle(ShortcutRecordActionStyle(saving: session.isRecording))
                .frame(width: Self.actionWidth, alignment: .leading)
                .disabled(session.isRecording && !session.canSave)
                .help(session.isRecording ? L10n.text("overlaykit.save.the.new.shortcut.esc.reverts") : L10n.text("overlaykit.record.a.global.shortcut.then.save.to"))
            }
        }
        .help(L10n.text("overlaykit.click.save.after.recording.esc.reverts.delete"))
    }

    private var label: String {
        if showsKeySymbols, !session.isRecording, let chord { return ShortcutKeySymbols.label(chord) }
        return session.label(for: chord, placeholder: placeholder)
    }

    private func toggle() {
        guard !session.isRecording else {
            session.stop()
            return
        }
        let binding = $chord
        let confirmation: Bool
        if case .confirmed = style { confirmation = true } else { confirmation = false }
        session.start(requiresConfirmation: confirmation, validate: validate,
                      onChord: { binding.wrappedValue = $0 }, onRecordingChange: onRecordingChange)
    }
}

private struct ShortcutRecordActionStyle: ButtonStyle {
    let saving: Bool
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SettingsTypography.caption)
            .frame(width: ShortcutRecorder.actionWidth, height: 29)
            .foregroundStyle(saving ? Color.white : Color.secondary)
            .background(saving ? Color.accentColor : Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(0.1), lineWidth: 0.5))
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
    }
}


private struct ShortcutKeycapButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        configuration.label
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor), in: shape)
            .overlay(shape.fill(.primary.opacity(configuration.isPressed ? 0.06 : 0)))
            .overlay(shape.strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
            .opacity(enabled ? 1 : 0.45)
    }
}
