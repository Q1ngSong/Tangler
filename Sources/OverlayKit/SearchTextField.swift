import AppKit

/// A plain single-line field that takes or gives up focus when asked, as soon as it is in a
/// window, and reports focus changes the user makes.
final class SearchTextField: NSTextField {
    var onFocusChange: ((Bool) -> Void)?

    var wantsFocus = false {
        didSet { if wantsFocus != oldValue { applyFocus() } }
    }

    /// An input method is composing, e.g. pinyin not yet turned into characters.
    var hasMarkedText: Bool { (currentEditor() as? NSTextView)?.hasMarkedText() ?? false }

    convenience init(fontSize: CGFloat) {
        self.init(frame: .zero)
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        usesSingleLineMode = true
        lineBreakMode = .byClipping
        cell?.isScrollable = true
        cell?.wraps = false
        font = .systemFont(ofSize: fontSize)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyFocus()
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusChange?(true) }
        return accepted
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        onFocusChange?(false)
    }

    /// The field editor is attached while the field has focus.
    private func applyFocus() {
        guard let window else { return }
        if wantsFocus, currentEditor() == nil {
            window.makeFirstResponder(self)
        } else if !wantsFocus, currentEditor() != nil {
            window.makeFirstResponder(nil)
        }
    }
}
