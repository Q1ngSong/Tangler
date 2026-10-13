import AppKit

/// Which Spaces an overlay panel appears on.
public enum OverlaySpaces: Equatable, Sendable {
    /// Every Space and over full-screen windows, kept out of Mission Control.
    case all
    /// Only the Space it was shown on, staying there whatever desktop shows and whichever app is
    /// active, and still out of Mission Control: a stationary panel, which Exposé leaves in place.
    case own
}

/// How an `OverlayPanel` behaves towards the keyboard and the mouse.
public struct OverlayStyle: Equatable {
    /// Lets the panel become the key window without activating Tangler, e.g. for the search field.
    public var acceptsKeyboard: Bool
    /// Clicks go to the windows below.
    public var passesMouseThrough: Bool
    /// The default sits above the Dock and the menu bar, so overlays cover every window.
    public var level: NSWindow.Level
    public var hasShadow: Bool
    public var spaces: OverlaySpaces

    public init(acceptsKeyboard: Bool = false, passesMouseThrough: Bool = false,
                level: NSWindow.Level = .statusBar, hasShadow: Bool = false, spaces: OverlaySpaces = .all) {
        self.acceptsKeyboard = acceptsKeyboard
        self.passesMouseThrough = passesMouseThrough
        self.level = level
        self.hasShadow = hasShadow
        self.spaces = spaces
    }

    /// Clickable without taking focus: switcher, Dock previews.
    public static var interactive: OverlayStyle { OverlayStyle() }
    /// Information only; clicks fall through: leader hints, snap previews.
    public static var hud: OverlayStyle { OverlayStyle(passesMouseThrough: true) }
    /// Takes the keyboard: the search panel.
    public static var keyboard: OverlayStyle { OverlayStyle(acceptsKeyboard: true) }
    /// Clickable, among ordinary windows on the Space it was shown on, e.g. a tab bar just above its
    /// window. macOS reports a Space switch only once its animation has ended, so a panel that had to
    /// be hidden then would ride along into the next Space; this one stays on its own.
    public static var attached: OverlayStyle { OverlayStyle(level: .normal, spaces: .own) }
    /// Covers everything, including menus, and takes Esc: the window picker.
    static var picker: OverlayStyle { OverlayStyle(acceptsKeyboard: true, level: .screenSaver) }
}
