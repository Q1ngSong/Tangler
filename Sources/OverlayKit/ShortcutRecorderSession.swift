import AppKit
import Contracts
import CoreKit
import Observation

/// One recording: watches this app's key presses through a local NSEvent monitor while
/// recording and turns them into a chord. The monitor is injected so tests need no events.
@MainActor
@Observable
final class ShortcutRecorderSession {
    typealias Install = @MainActor (@escaping (NSEvent) -> NSEvent?) -> Any?
    typealias Remove = @MainActor (Any) -> Void

    private(set) var isRecording = false
    private(set) var heldModifiers: Modifiers = []
    /// Why the last press was refused; cleared by the next accepted press.
    private(set) var problem: String?
    private(set) var draft: KeyChord?
    private(set) var hasDraft = false
    var canSave: Bool { isRecording && hasDraft && problem == nil }

    /// Only one editor may own keyboard capture and suspend global shortcuts at a time.
    private static weak var active: ShortcutRecorderSession?
    @ObservationIgnored private var requiresConfirmation = false
    @ObservationIgnored private var validate: ((KeyChord?) -> String?)?

    @ObservationIgnored private let install: Install
    @ObservationIgnored private let remove: Remove
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var onChord: ((KeyChord?) -> Void)?
    @ObservationIgnored private var onRecordingChange: ((Bool) -> Void)?
    @ObservationIgnored private var lastOutcome: ShortcutRecording.Outcome?

    init(install: @escaping Install = ShortcutRecorderSession.installLocalMonitor,
         remove: @escaping Remove = { NSEvent.removeMonitor($0) }) {
        self.install = install
        self.remove = remove
    }

    /// `onChord` gets the recorded chord, or nil when the user removed it with Delete.
    func start(requiresConfirmation: Bool = false, validate: ((KeyChord?) -> String?)? = nil,
               onChord: @escaping (KeyChord?) -> Void, onRecordingChange: ((Bool) -> Void)? = nil) {
        guard !isRecording else { return }
        Self.active?.stop()
        Self.active = self
        self.requiresConfirmation = requiresConfirmation
        self.validate = validate
        self.onChord = onChord
        self.onRecordingChange = onRecordingChange
        isRecording = true
        problem = nil
        draft = nil
        hasDraft = false
        monitor = install { [weak self] event in self?.handle(event) ?? event }
        onRecordingChange?(true)
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        heldModifiers = []
        problem = nil
        draft = nil
        hasDraft = false
        validate = nil
        if Self.active === self { Self.active = nil }
        if let monitor { remove(monitor) }
        monitor = nil
        let notify = onRecordingChange
        onChord = nil
        onRecordingChange = nil
        notify?(false)
    }

    /// Revalidate at Save as another setting may have changed since the key press.
    func save() {
        guard canSave else { return }
        if let reason = validate?(draft) { problem = reason; return }
        finish(reporting: draft)
    }

    /// Returns true when the press is consumed, which is every press while recording.
    func keyDown(keyCode: UInt16, flags: NSEvent.ModifierFlags, isRepeat: Bool) -> Bool {
        guard isRecording else { return false }
        guard !isRepeat else { return true }
        if requiresConfirmation, ShortcutRecording.modifiers(from: flags).isEmpty {
            if KeyCodes.name(for: keyCode) == "tab" { return false }
            if KeyCodes.name(for: keyCode) == "return", canSave { save(); return true }
        }
        let outcome = ShortcutRecording.outcome(keyCode: keyCode, modifierFlags: flags)
        lastOutcome = outcome
        switch outcome {
        case .record(let chord): accept(chord)
        case .clear: accept(nil)
        case .cancel: stop()
        case .reject(let reason): problem = reason
        }
        return true
    }

    private func accept(_ chord: KeyChord?) {
        problem = validate?(chord)
        if requiresConfirmation {
            draft = chord
            hasDraft = true
        } else if problem == nil {
            finish(reporting: chord)
        }
    }

    func flagsChanged(_ flags: NSEvent.ModifierFlags) {
        guard isRecording else { return }
        heldModifiers = ShortcutRecording.modifiers(from: flags)
    }

    func label(for chord: KeyChord?, placeholder: String) -> String {
        guard isRecording else { return chord?.description ?? placeholder }
        if let problem { return problem }
        if hasDraft { return draft.map(ShortcutKeySymbols.label) ?? L10n.text("overlaykit.clear.shortcut") }
        return heldModifiers.isEmpty ? L10n.text("overlaykit.press.a.key.combination") : "\(heldModifiers)…"
    }

    private func finish(reporting chord: KeyChord?) {
        let report = onChord
        stop()
        report?(chord)
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .keyDown:
            guard keyDown(keyCode: event.keyCode, flags: event.modifierFlags, isRepeat: event.isARepeat) else {
                return event
            }
            if case .reject = lastOutcome { NSSound.beep() }
            return nil
        case .flagsChanged:
            flagsChanged(event.modifierFlags)
            return event
        default:
            return event
        }
    }

    static func installLocalMonitor(_ handler: @escaping (NSEvent) -> NSEvent?) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged], handler: handler)
    }
}
