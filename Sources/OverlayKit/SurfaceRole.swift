import SwiftUI

// Roles only dispatch to the skins; no glass API is written in this file (Liquid Glass skin
// design 3.3).

/// Which overlay the one shell belongs to.
public enum PanelKind: Hashable, Sendable {
    case switcher, dockPreview, palette, notice, toast, report, tabBar, tabGhost
    /// The leader's hint panel; `dimmed` while it lingers after a command.
    case hints(dimmed: Bool)
}

public enum CardState: Hashable, Sendable { case rest, hover, selected }
/// `incoming` is a tab a drag would put in the bar, or one being moved within it.
public enum TabState: Hashable, Sendable { case rest, hover, active, incoming }
public enum ChipSize: Hashable, Sendable { case regular, small }

/// What an element of an overlay is for. Call sites name the role; the skin picks the paint.
public enum SurfaceRole: Hashable, Sendable {
    /// The overlay's shell.
    case panel(PanelKind)
    /// A `ThumbnailCard`; `slide` lets the selection slide from card to card.
    case card(CardState, slide: Namespace.ID? = nil)
    /// The thumbnail area inside a card; it also clips.
    case well
    /// The search band at the top of a list panel, including its 1 pt separator.
    case field(bandHeight: CGFloat)
    /// The results under the search band.
    case results
    /// A list row selected with the keyboard.
    case selection(Bool)
    /// A key cap.
    case chip(ChipSize)
    /// A prompt floating over other apps' windows.
    case label
    /// The dimming over a display while picking a window.
    case scrim
    /// One tab of a tab bar.
    case tab(TabState)
    /// A ring around a panel something is being dragged onto, following the panel's own shape.
    case dropTarget(PanelKind)
}

public extension View {
    /// Paints the view as `role` in the current skin.
    func surface(_ role: SurfaceRole) -> some View { modifier(SurfaceModifier(role: role)) }
}

struct SurfaceModifier: ViewModifier {
    let role: SurfaceRole
    @Environment(\.skin) private var skin
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        switch skin {
        case .classic:
            ClassicSkin.paint(content, as: role)
        case .liquidGlass:
            LiquidGlassSkin.paint(content, as: role, strong: contrast == .increased, reduceMotion: reduceMotion)
        }
    }
}

/// The small icon-only buttons in overlays.
public enum OverlayControlKind: Hashable, Sendable {
    /// Minimize or close in a card's header.
    case card
    /// A tab's ×.
    case tabClose
}

/// A primitive style, because the classic skin keeps `.plain`'s dimming on press: each skin
/// wraps `Button(action: configuration.trigger)` and also sizes the label and draws its
/// backing. Call sites write `Button(action:) { Image(systemName:) }.buttonStyle(.overlayControl(kind))`.
public struct OverlayControlButtonStyle: PrimitiveButtonStyle {
    let kind: OverlayControlKind

    public func makeBody(configuration: Configuration) -> some View {
        SkinnedControl(kind: kind, configuration: configuration)
    }

    private struct SkinnedControl: View {
        let kind: OverlayControlKind
        let configuration: PrimitiveButtonStyleConfiguration
        @Environment(\.skin) private var skin

        var body: some View {
            switch skin {
            case .classic: ClassicSkin.control(kind, configuration)
            case .liquidGlass: LiquidGlassSkin.control(kind, configuration)
            }
        }
    }
}

public extension PrimitiveButtonStyle where Self == OverlayControlButtonStyle {
    static func overlayControl(_ kind: OverlayControlKind) -> Self { OverlayControlButtonStyle(kind: kind) }
}
