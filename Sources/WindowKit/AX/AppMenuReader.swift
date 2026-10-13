import ApplicationServices
import Foundation

/// Reads an application's menu bar through Accessibility: the first menus, and one level into the
/// items that say "new window" (workspaces design 5.3). Reading does not open any menu on screen.
enum AppMenuReader {
    /// The Apple menu, the application menu and the next four; "new window" is in one of them.
    static let menusRead = 6
    /// A timeout belongs to the element it is set on and is not inherited by the elements read
    /// from it, so it is set on every element this reader obtains.
    private static let timeout: Float = 1.0
    private static let attributes = [kAXTitleAttribute, "AXMenuItemCmdChar", "AXMenuItemCmdModifiers",
                                     kAXEnabledAttribute, kAXChildrenAttribute]

    /// nil when the menus could not be read, as while the application is busy: that is not "no
    /// such item". An application without a menu bar has no items.
    static func items(of pid: Int32) -> [AppMenuItem]? {
        guard let found = menuBar(of: pid) else { return nil }
        guard let bar = found else { return [] }
        guard let tops = listed(bar) else { return nil }
        var result: [AppMenuItem] = []
        for (menuIndex, top) in tops.prefix(menusRead).enumerated() {
            guard let menus = listed(top) else { return nil }
            guard let menu = menus.first else { continue }
            guard let elements = listed(menu) else { return nil }
            for (itemIndex, element) in elements.enumerated() {
                guard let item = describe(element, parent: nil, path: [menuIndex, itemIndex]) else { return nil }
                result.append(item)
                guard item.hasSubmenu, NewWindowMenu.isNewWindowTitle(item.title) else { continue }
                guard let submenus = listed(element) else { return nil }
                guard let submenu = submenus.first else { continue }
                guard let inside = listed(submenu) else { return nil }
                for (childIndex, child) in inside.enumerated() {
                    guard var inner = describe(child, parent: item.title, path: [menuIndex, itemIndex, childIndex]) else {
                        return nil
                    }
                    // A disabled menu disables what is in it.
                    inner.isEnabled = inner.isEnabled && item.isEnabled
                    result.append(inner)
                }
            }
        }
        return result
    }

    /// What a read says: its value; `absent` when the element answered that it has no such thing,
    /// as an application without a menu bar does; nil when it did not answer, which says nothing
    /// about what is there.
    static func answer<Value>(_ read: Result<Value, AXFailure>, absent: Value) -> Value? {
        switch read {
        case .success(let value): return value
        case .failure(.unsupported): return absent
        case .failure: return nil
        }
    }

    /// Presses the item at `item.path` if it is still the item that was read: the same title and,
    /// in a submenu, the same parent title (Terminal lists the same profile names under "new
    /// window" and under "new tab"). False means nothing was sent.
    static func press(_ item: AppMenuItem, of pid: Int32) -> Bool {
        guard let bar = menuBar(of: pid) ?? nil, item.path.count == (item.parentTitle == nil ? 2 : 3) else { return false }
        let menus = children(bar)
        guard menus.indices.contains(item.path[0]), let menu = children(menus[item.path[0]]).first else { return false }
        let siblings = children(menu)
        guard siblings.indices.contains(item.path[1]) else { return false }
        var target = siblings[item.path[1]]
        if let parentTitle = item.parentTitle {
            guard title(of: target) == parentTitle, let submenu = children(target).first else { return false }
            let inner = children(submenu)
            guard inner.indices.contains(item.path[2]) else { return false }
            target = inner[item.path[2]]
        }
        guard title(of: target) == item.title else { return false }
        // Sent is sent, whatever the answer: a slow application answers "cannot complete" and
        // opens the window all the same. Whether a window came is read from the window list.
        _ = AXUIElementPerformAction(target, kAXPressAction as CFString)
        return true
    }

    /// nil when the application did not answer; `.some(nil)` when it has no menu bar.
    private static func menuBar(of pid: Int32) -> AXUIElement?? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        guard let value = answer(AXRead.value(app, kAXMenuBarAttribute).map(Optional.some), absent: nil) else { return nil }
        guard let bar = AXRead.element(value) else { return .some(nil) }
        AXUIElementSetMessagingTimeout(bar, timeout)
        return bar
    }

    /// An element's children; nil when they could not be read.
    private static func listed(_ element: AXUIElement) -> [AXUIElement]? {
        let read = AXRead.value(element, kAXChildrenAttribute).map { $0 as? [AXUIElement] ?? [] }
        guard let found = answer(read, absent: []) else { return nil }
        found.forEach { AXUIElementSetMessagingTimeout($0, timeout) }
        return found
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        listed(element) ?? []
    }

    private static func title(of element: AXUIElement) -> String? {
        AXRead.string(AXRead.attribute(element, kAXTitleAttribute))
    }

    /// nil when the item could not be read: it might be the one that is looked for.
    private static func describe(_ element: AXUIElement, parent: String?, path: [Int]) -> AppMenuItem? {
        guard let values = answer(AXRead.attributes(element, attributes), absent: [nil, nil, nil, nil, nil]) else { return nil }
        return AppMenuItem(title: AXRead.string(values[0]) ?? "", parentTitle: parent, keyCharacter: AXRead.string(values[1]),
                           modifiers: (values[2] as? NSNumber)?.intValue,
                           hasSubmenu: !((values[4] as? [AXUIElement]) ?? []).isEmpty,
                           isEnabled: AXRead.bool(values[3]) ?? true, path: path)
    }
}
