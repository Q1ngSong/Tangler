import AppKit
import SwiftUI

/// A text field whose focus the owner controls, with callbacks for Esc, Return and the up and
/// down arrows (also ⌃P and ⌃N). A key with no callback keeps its normal editing behaviour.
/// Keys an input method needs while composing never reach the callbacks.
/// In an overlay, use an `OverlayStyle.keyboard` host so the panel can become key.
public struct SearchField: View {
    private let placeholder: String
    @Binding private var text: String
    @Binding private var isFocused: Bool
    private let fontSize: CGFloat
    private let callbacks: SearchFieldCallbacks

    public init(_ placeholder: String, text: Binding<String>, isFocused: Binding<Bool>, fontSize: CGFloat = 16,
                onEscape: (() -> Void)? = nil, onSubmit: (() -> Void)? = nil,
                onMoveUp: (() -> Void)? = nil, onMoveDown: (() -> Void)? = nil) {
        self.placeholder = placeholder
        _text = text
        _isFocused = isFocused
        self.fontSize = fontSize
        callbacks = SearchFieldCallbacks(onEscape: onEscape, onSubmit: onSubmit, onMoveUp: onMoveUp, onMoveDown: onMoveDown)
    }

    public var body: some View {
        SearchFieldRepresentable(placeholder: placeholder, text: $text, isFocused: $isFocused,
                                 fontSize: fontSize, callbacks: callbacks)
    }
}

struct SearchFieldCallbacks {
    var onEscape: (() -> Void)?
    var onSubmit: (() -> Void)?
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?

    func action(for command: SearchFieldCommand) -> (() -> Void)? {
        switch command {
        case .cancel: return onEscape
        case .submit: return onSubmit
        case .moveUp: return onMoveUp
        case .moveDown: return onMoveDown
        }
    }
}

struct SearchFieldRepresentable: NSViewRepresentable {
    var placeholder: String
    @Binding var text: String
    @Binding var isFocused: Bool
    var fontSize: CGFloat
    var callbacks: SearchFieldCallbacks

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> SearchTextField {
        let field = SearchTextField(fontSize: fontSize)
        field.delegate = context.coordinator
        field.onFocusChange = { [weak coordinator = context.coordinator] focused in coordinator?.focusChanged(focused) }
        return field
    }

    func updateNSView(_ field: SearchTextField, context: Context) {
        context.coordinator.parent = self
        if field.placeholderString != placeholder { field.placeholderString = placeholder }
        // Replacing the text during composition would throw away what the input method holds.
        if field.stringValue != text, !field.hasMarkedText { field.stringValue = text }
        field.wantsFocus = isFocused
    }

    /// Fills the offered width; NSTextField would otherwise size itself to its text.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SearchTextField, context: Context) -> CGSize? {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 320
        return CGSize(width: width, height: nsView.intrinsicContentSize.height)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchFieldRepresentable

        init(_ parent: SearchFieldRepresentable) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard let command = SearchFieldCommand(selector: selector, hasMarkedText: textView.hasMarkedText()),
                  let action = parent.callbacks.action(for: command) else { return false }
            action()
            return true
        }

        func focusChanged(_ focused: Bool) {
            guard parent.isFocused != focused else { return }
            let binding = parent.$isFocused
            // Focus can change while SwiftUI is updating the view, e.g. from updateNSView.
            DispatchQueue.main.async { binding.wrappedValue = focused }
        }
    }
}
