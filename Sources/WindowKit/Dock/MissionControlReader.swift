import AppKit
import ApplicationServices
import Contracts

/// Reads Mission Control's Spaces bar from the Dock's accessibility tree, which exists only while
/// Mission Control is open (workspaces design 2.1):
/// `mc` › `mc.display` › `mc.spaces` › `mc.spaces.list` (one button per Space) and `mc.spaces.add`.
enum MissionControlReader {
    private static let dockBundleID = "com.apple.dock"
    /// The Dock answers slower than `AXRead.timeout` while Mission Control animates. A timeout
    /// belongs to the element it is set on and is not inherited by the elements read from it, so
    /// it is set on every element this reader obtains.
    private static let timeout: Float = 1.0

    /// Whether Mission Control is showing; nil when that cannot be told: the Dock is not running,
    /// did not give its children, or did not say what one of them is. The other reads here take
    /// what they cannot read for absent, which ends in "not found"; here it would end in "closed".
    static func isOpen() -> Bool? {
        guard let app = dock(), case .success(let value) = AXRead.value(app, kAXChildrenAttribute),
              let found = value as? [AXUIElement] else { return nil }
        for element in found {
            AXUIElementSetMessagingTimeout(element, timeout)
            switch AXRead.value(element, "AXIdentifier") {
            case .success(let id): if AXRead.string(id) == "mc" { return true }
            case .failure(.unsupported): continue
            case .failure: return nil
            }
        }
        return false
    }

    /// The bar's buttons, left to right; nil when Mission Control is closed or looks different,
    /// and for the whole bar when the Dock did not give one button's frame or title. A missing
    /// frame would equal the next missing frame, and a missing title would be a title without a
    /// number: both would pass the caller's checks exactly when the Dock is too slow to answer.
    static func buttons(on display: DisplayID) -> [SpaceButton]? {
        guard let list = bar(on: display).flatMap({ child($0, "mc.spaces.list") }) else { return nil }
        var buttons: [SpaceButton] = []
        for element in children(list) {
            guard let frame = try? AXRead.frame(of: element).get(), let title = title(of: element) else { return nil }
            buttons.append(SpaceButton(title: title, frame: frame, actions: actions(of: element)))
        }
        return buttons
    }

    /// Presses "add desktop". False means only that the button was not found and nothing was
    /// sent. Once the press is sent the answer is true whatever the accessibility call returns:
    /// an error such as "cannot complete" says the Dock did not answer in time, not that the
    /// request did not reach it. Whether a desktop appeared is for the caller to read from the
    /// Space list.
    static func pressAdd(on display: DisplayID) -> Bool {
        guard let add = bar(on: display).flatMap({ child($0, "mc.spaces.add") }) else { return false }
        _ = AXUIElementPerformAction(add, kAXPressAction as CFString)
        return true
    }

    /// Performs an action on the button at `position` of a bar the caller read with `count`
    /// buttons. False means only that nothing was sent: the button was not found, or the bar,
    /// read again here, has another number of buttons by now and the position may be another
    /// Space's. Once the action is sent the answer is true whatever the accessibility call
    /// returns, as for `pressAdd`.
    static func perform(_ action: String, onButton position: Int, of count: Int, on display: DisplayID) -> Bool {
        guard let list = bar(on: display).flatMap({ child($0, "mc.spaces.list") }) else { return false }
        let buttons = children(list)
        guard buttons.count == count, buttons.indices.contains(position) else { return false }
        _ = AXUIElementPerformAction(buttons[position], action as CFString)
        return true
    }

    /// The Dock's application element; nil when the Dock is not running.
    private static func dock() -> AXUIElement? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: dockBundleID).first else { return nil }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(app, timeout)
        return app
    }

    private static func root() -> AXUIElement? {
        dock().flatMap { child($0, "mc") }
    }

    /// The Spaces bar of the display whose number maps to `display`; with a single display, that one.
    private static func bar(on display: DisplayID) -> AXUIElement? {
        guard let root = root() else { return nil }
        let displays = children(root).filter { identifier($0) == "mc.display" }
        let match = displays.first { element in
            guard let number = (AXRead.attribute(element, "AXDisplayID") as? NSNumber)?.uint32Value else { return false }
            return ScreenReader.uuid(of: number) == display.rawValue
        } ?? (displays.count == 1 ? displays.first : nil)
        return match.flatMap { child($0, "mc.spaces") }
    }

    /// An element's children, each given this reader's timeout.
    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        let found = AXRead.attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
        found.forEach { AXUIElementSetMessagingTimeout($0, timeout) }
        return found
    }

    private static func identifier(_ element: AXUIElement) -> String? {
        AXRead.string(AXRead.attribute(element, "AXIdentifier"))
    }

    private static func child(_ element: AXUIElement, _ id: String) -> AXUIElement? {
        children(element).first { identifier($0) == id }
    }

    /// A button's title: empty when the button has none, nil when the Dock did not say.
    private static func title(of element: AXUIElement) -> String? {
        switch AXRead.value(element, kAXTitleAttribute) {
        case .success(let value): return AXRead.string(value) ?? ""
        case .failure(.unsupported): return ""
        case .failure: return nil
        }
    }

    private static func actions(of element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return names as? [String] ?? []
    }
}
