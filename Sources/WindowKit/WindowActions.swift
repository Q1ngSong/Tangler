import AppKit
import ApplicationServices
import Contracts

/// Focus, minimize and close through Accessibility, with precise focus when available.
struct WindowActions: @unchecked Sendable {
    let preciseFocus: PreciseFocus?

    func minimize(_ element: AXUIElement) -> AXFailure? {
        AXUIElementSetMessagingTimeout(element, AXRead.timeout)
        return AXRead.set(element, kAXMinimizedAttribute, kCFBooleanTrue)
    }

    func close(_ element: AXUIElement) -> AXFailure? {
        AXUIElementSetMessagingTimeout(element, AXRead.timeout)
        guard let button = AXRead.element(AXRead.attribute(element, kAXCloseButtonAttribute)) else { return .unsupported }
        AXUIElementSetMessagingTimeout(button, AXRead.timeout)
        return AXFailure(AXUIElementPerformAction(button, kAXPressAction as CFString))
    }

    /// Restores the window if minimized, brings its app forward and raises it. Whether focus
    /// actually moved is checked separately with `isFocused`, since activation is asynchronous.
    /// `precise` says whether the window server took the precise request; when it did not, the
    /// caller activates the app itself.
    func focus(_ element: AXUIElement, id: WindowID, pid: Int32) -> (failure: AXFailure?, precise: Bool) {
        AXUIElementSetMessagingTimeout(element, AXRead.timeout)
        // Read live: the inventory may not have seen a minimize yet.
        if AXRead.bool(AXRead.attribute(element, kAXMinimizedAttribute)) == true,
           let failure = AXRead.set(element, kAXMinimizedAttribute, kCFBooleanFalse) { return (failure, false) }
        let precise = preciseFocus?.focus(id, pid: pid) == true
        if !precise {
            // Public fallback (design section 5.2): the window becomes its app's main window and the
            // caller activates the app without `.activateAllWindows`. Setting the app's AXFrontmost
            // instead brings every one of its windows forward (tab groups design 2.1).
            AXRead.set(element, kAXMainAttribute, kCFBooleanTrue)
        }
        let raised = AXFailure(AXUIElementPerformAction(element, kAXRaiseAction as CFString))
        return (raised == .invalidElement || raised == .apiDisabled ? raised : nil, precise)
    }

    /// Brings the window to the front of its app's windows; does nothing for an inactive app.
    func raise(_ element: AXUIElement) -> AXFailure? {
        AXUIElementSetMessagingTimeout(element, AXRead.timeout)
        return AXFailure(AXUIElementPerformAction(element, kAXRaiseAction as CFString))
    }

    func isFocused(_ element: AXUIElement, pid: Int32) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let focused = AXRead.element(AXRead.attribute(AXRead.application(pid), kAXFocusedWindowAttribute)) else { return false }
        return CFEqual(focused, element)
    }

    /// Fallback when AppKit refuses to hide the app.
    func hideThroughAccessibility(pid: Int32) -> AXFailure? {
        AXRead.set(AXRead.application(pid), kAXHiddenAttribute, kCFBooleanTrue)
    }
}
