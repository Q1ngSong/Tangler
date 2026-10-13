import CoreKit
import Foundation

/// macOS's own window tiling (系统设置 › 桌面与程序坞 › 窗口), which reacts to the same drags
/// as Tangler. Only ever read: the settings page points the user there instead (design 1.4).
struct SystemTiling: Equatable, Sendable {
    /// 拖移窗口至屏幕左或右边缘实现平铺
    var edgeDrag: Bool
    /// 拖移窗口至菜单栏以充满屏幕
    var menuBarDrag: Bool
    /// 拖移窗口时按住⌥键实现平铺
    var optionDrag: Bool

    static var edgeConflict: String { L10n.text("windowlayout.drag.windows.to.left.or.right.edge") }
    static var menuBarConflict: String { L10n.text("windowlayout.drag.windows.to.menu.bar.to.fill") }
    static var optionConflict: String { L10n.text("windowlayout.hold.key.while.dragging.windows.to.tile") }

    /// `value(domain, key)` returns a stored preference. A missing tiling key means on, the
    /// system default; tiling is off altogether while displays share Spaces.
    static func read(_ value: (_ domain: String, _ key: String) -> Any?) -> SystemTiling {
        if flag(value("com.apple.spaces", "spans-displays")) == true {
            return SystemTiling(edgeDrag: false, menuBarDrag: false, optionDrag: false)
        }
        let windowManager = "com.apple.WindowManager"
        return SystemTiling(edgeDrag: flag(value(windowManager, "EnableTilingByEdgeDrag")) ?? true,
                            menuBarDrag: flag(value(windowManager, "EnableTopTilingByEdgeDrag")) ?? true,
                            optionDrag: flag(value(windowManager, "EnableTilingOptionAccelerator")) ?? true)
    }

    /// The current user's preferences, re-read from disk so changes made in System Settings count.
    static func current() -> SystemTiling {
        read { domain, key in
            CFPreferencesAppSynchronize(domain as CFString)
            return CFPreferencesCopyAppValue(key as CFString, domain as CFString)
        }
    }

    /// One line for each system option that fights a Tangler feature that is switched on.
    func conflicts(with settings: LayoutSettings) -> [String] {
        var lines: [String] = []
        if settings.edgeSnapping && edgeDrag { lines.append(Self.edgeConflict) }
        if settings.edgeSnapping && menuBarDrag { lines.append(Self.menuBarConflict) }
        if settings.grid && settings.gridModifiers.contains(.option) && optionDrag { lines.append(Self.optionConflict) }
        return lines
    }

    private static func flag(_ value: Any?) -> Bool? {
        (value as? NSNumber)?.boolValue
    }
}
