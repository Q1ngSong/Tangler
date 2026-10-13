import Foundation

/// One item of an application's menu bar, as read through Accessibility.
struct AppMenuItem: Equatable {
    var title: String
    /// For an item one level down: the title of the item whose submenu holds it.
    var parentTitle: String? = nil
    /// The shortcut's key; nil when the item has none. It can be an empty string for a shortcut on a
    /// key that has no character.
    var keyCharacter: String? = nil
    /// The shortcut's modifiers, a bit mask in Accessibility's encoding: 1 Shift, 2 Option, 4 Control,
    /// and 8 when the shortcut does not use Command. So 0 is plain Command and 1 is Shift-Command.
    var modifiers: Int? = nil
    var hasSubmenu = false
    /// A disabled item cannot be pressed.
    var isEnabled = true
    /// Positions from the menu bar down: menu, item and, in a submenu, the item there.
    var path: [Int] = []
}

/// Picks the menu item that opens another window of the application (workspaces design 5.3).
/// Titles differ between applications and languages, so this is a rule of thumb; an application
/// it gets wrong is handled by the workspace item's own window setting.
enum NewWindowMenu {
    /// Words that mark a private window or another profile's: never the plain "new window".
    private static let special = ["无痕", "隐私", "隐身", "私密", "private", "incognito", "profile"]

    /// ⌘N first, then ⇧⌘N, then the order in the menu.
    static func choose(from items: [AppMenuItem]) -> AppMenuItem? {
        let candidates = items.filter { item in
            guard item.isEnabled, !item.hasSubmenu else { return false }
            // One level down, an item counts by the menu it is in, not by its own title: Terminal
            // lists its profiles under "新建窗口". The reader only goes into such menus, which also
            // keeps "tmux ▸ New Window" out.
            if let parent = item.parentTitle {
                // ⌘N is the menu's default whatever it is called: a profile named "My Profile" still counts.
                return isNewWindowTitle(parent) && (shortcut(of: item) == 0 || !isSpecial(item.title))
            }
            return isNewWindowTitle(item.title)
        }
        return candidates.first { shortcut(of: $0) == 0 } ?? candidates.first { shortcut(of: $0) == 1 } ?? candidates.first
    }

    /// "新建…窗口", "打开新的窗口", "New … Window": the title has to start that way, and must not
    /// name a private window, a profile or a tab.
    static func isNewWindowTitle(_ title: String) -> Bool {
        let text = title.lowercased()
        guard !isSpecial(text) else { return false }
        if text.contains("窗口") { return text.hasPrefix("新建") || text.hasPrefix("打开新的") }
        let words = text.split(whereSeparator: { !$0.isLetter })
        return words.first == "new" && words.contains("window") && !words.contains("tab")
    }

    private static func isSpecial(_ title: String) -> Bool {
        let text = title.lowercased()
        return special.contains(where: text.contains)
    }

    /// The modifiers of an item whose shortcut key is N; nil for any other item.
    private static func shortcut(of item: AppMenuItem) -> Int? {
        item.keyCharacter?.uppercased() == "N" ? item.modifiers : nil
    }
}
