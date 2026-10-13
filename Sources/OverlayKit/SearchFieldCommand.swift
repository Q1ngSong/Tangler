import AppKit

/// A key the search field hands to its owner instead of editing text. Recognising the
/// key-binding selectors, not key codes, also covers ⌃P and ⌃N for up and down.
enum SearchFieldCommand: Equatable, Sendable {
    case cancel, submit, moveUp, moveDown

    /// nil for ordinary editing, and for every key while an input method is composing:
    /// Return and Esc then confirm or cancel the composition, as Chinese input needs.
    init?(selector: Selector, hasMarkedText: Bool) {
        guard !hasMarkedText else { return nil }
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)): self = .cancel
        case #selector(NSResponder.insertNewline(_:)): self = .submit
        case #selector(NSResponder.moveUp(_:)): self = .moveUp
        case #selector(NSResponder.moveDown(_:)): self = .moveDown
        default: return nil
        }
    }
}
