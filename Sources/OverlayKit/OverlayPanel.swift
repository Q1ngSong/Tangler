import AppKit

/// A borderless, transparent panel. By default it floats above every window, on every Space and
/// over full-screen windows; `OverlayStyle.spaces` can keep it on one Space instead. It never
/// activates Tangler; with `OverlayStyle.acceptsKeyboard` it can still become the key window so
/// a search field receives typing.
@MainActor
public final class OverlayPanel: NSPanel {
    /// `.nonactivatingPanel` only takes effect when passed to the initializer.
    static let windowStyleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
    /// `.transient` keeps these overlays out of Mission Control.
    static let spacesBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                                              .transient, .ignoresCycle]
    /// On the one Space it was shown on. `.stationary` keeps it out of Mission Control and, unlike
    /// `.transient`, on its Space: a transient panel is carried to the Space showing when the
    /// desktop changes while Tangler is the active app, or when a window of Tangler's on another
    /// desktop becomes key (measured 2026-10-11, see OverlaySpacesTests). A `.managed` panel stays
    /// too, but shows in Mission Control as a window of its own (tab groups design 11). Exposé
    /// leaves a stationary window where it is.
    static let ownSpaceBehavior: NSWindow.CollectionBehavior = [.stationary, .ignoresCycle]

    public var style: OverlayStyle {
        didSet { applyStyle() }
    }

    /// Invisible and deaf to the mouse where it stands, still on screen and on its Space. For
    /// hiding a panel that must stay on its desktop: one ordered out and in again while another
    /// desktop shows lands on that one (OverlaySpacesTests).
    public var isConcealed = false {
        didSet { applyConcealment() }
    }

    public init(style: OverlayStyle = .interactive) {
        self.style = style
        super.init(contentRect: .zero, styleMask: Self.windowStyleMask, backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        isExcludedFromWindowsMenu = true
        worksWhenModal = true
        animationBehavior = .none
        applyStyle()
    }

    public override var canBecomeKey: Bool { style.acceptsKeyboard }
    public override var canBecomeMain: Bool { false }

    private func applyConcealment() {
        alphaValue = isConcealed ? 0 : 1
        ignoresMouseEvents = isConcealed || style.passesMouseThrough
    }

    private func applyStyle() {
        ignoresMouseEvents = isConcealed || style.passesMouseThrough
        hasShadow = style.hasShadow
        level = style.level
        switch style.spaces {
        case .all: collectionBehavior = Self.spacesBehavior
        case .own: collectionBehavior = Self.ownSpaceBehavior
        }
    }
}
