import AppKit
import SwiftUI

/// Every Liquid Glass paint lives here (Liquid Glass skin design 3.4): one regular glass per
/// overlay, or side-by-side glass in one container; flat fills on the glass; never tinted,
/// because overlays live in an app that is never active, where a tint turns grey.
enum LiquidGlassSkin {
    // Concentric: inner = outer − padding (WWDC25-356). SkinGeometryTests pins the pairs that
    // cross into the feature modules' layout constants.
    static let switcherRadius: CGFloat = 24
    static let dockRadius: CGFloat = 22
    /// = switcher 24 − strip padding 10 = Dock 22 − padding 8.
    static let cardRadius: CGFloat = 14
    /// 7: the card's radius less its padding.
    static let wellRadius = cardRadius - ThumbnailCardLayout.padding
    static let resultsRadius: CGFloat = 24
    /// 24 − the palette's list padding 6.
    static let rowRadius: CGFloat = 18
    /// Between the search capsule and the results.
    static let fieldGap: CGFloat = 8
    /// Below `fieldGap`, so the capsule and the results stay apart at rest.
    static let paletteContainerSpacing: CGFloat = 6
    /// The hint panel's content while lingering, as far as classic fades its whole panel; the
    /// glass itself stays at full strength.
    static let hintsDimmedOpacity = 0.5
    static func chipRadius(_ size: ChipSize) -> CGFloat { size == .regular ? 7 : 6 }
    // Key caps take classic's values, fill and hairline, so they stay visible while the hint
    // panel lingers. `strong` is increased contrast.
    static func chipFill(strong: Bool) -> Double { strong ? 0.18 : 0.1 }
    static func chipStroke(strong: Bool) -> Double { strong ? 0.4 : 0.15 }
    static let chipStrokeWidth: CGFloat = 0.5
    // A tab a drag would add, and the ring around the bar it would join. The accent means
    // something here: a flat fill and a solid line on the glass, never a tint.
    static let tabIncomingFill = 0.16
    static func tabIncomingStrokeWidth(strong: Bool) -> CGFloat { strong ? 2 : 1 }
    static let tabIncomingDash: [CGFloat] = [4, 3]
    static func dropRingWidth(strong: Bool) -> CGFloat { strong ? 3 : 2 }
    /// `glassZone` is the accent inside a snap zone of real glass: a wash that tells it from
    /// plain blur, and a thin rim that keeps its edge readable over an empty desktop.
    static let zones = ZoneStyles(zone: ZoneStyle(cornerRadius: 16, fillOpacity: 0.16, strokeOpacity: 0.85, lineWidth: 2),
                                  gridCell: ZoneStyle(cornerRadius: 10, fillOpacity: 0.05, strokeOpacity: 0.25, lineWidth: 1),
                                  glassZone: ZoneStyle(cornerRadius: 16, fillOpacity: 0.2, strokeOpacity: 0.6, lineWidth: 1.5))

    /// A shell's fixed corner radius, or nil for a capsule, whose height decides (the tab bar's
    /// glass is (h − 2) / 2).
    static func panelRadius(_ kind: PanelKind) -> CGFloat? {
        switch kind {
        case .switcher, .palette: switcherRadius
        case .dockPreview: dockRadius
        case .hints: 18
        case .notice, .report: 20
        case .toast, .tabBar, .tabGhost: nil
        }
    }

    static func panelShape(_ kind: PanelKind) -> AnyShape {
        if let radius = panelRadius(kind) {
            AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            AnyShape(Capsule())
        }
    }

    /// The ring of `.dropTarget`: `AnyShape` cannot stroke its border, so each shape does its own.
    @ViewBuilder
    static func dropRing(_ kind: PanelKind, width: CGFloat) -> some View {
        if let radius = panelRadius(kind) {
            RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.accentColor, lineWidth: width)
        } else {
            Capsule().strokeBorder(Color.accentColor, lineWidth: width)
        }
    }

    /// A snap zone of real glass at `frame`: regular and untinted, because a tint turns grey in
    /// an app that is never active; `accent` is painted inside its content view instead. It is
    /// AppKit glass, not SwiftUI's: the snap preview is drawn with Core Animation and animates
    /// this view's layer.
    @MainActor
    static func zoneGlass(accent: ZoneStyle, frame: CGRect) -> NSView {
        let glass = NSGlassEffectView(frame: frame)
        glass.style = .regular
        glass.cornerRadius = accent.cornerRadius
        let content = NSView(frame: CGRect(origin: .zero, size: frame.size))
        content.wantsLayer = true
        if let layer = content.layer { accent.paint(layer) }
        glass.contentView = content
        return glass
    }

    @ViewBuilder
    static func paint<V: View>(_ content: V, as role: SurfaceRole, strong: Bool, reduceMotion: Bool) -> some View {
        switch role {
        case .panel(.palette):
            // Spotlight: the field capsule (.field) and the results (.results) are two glasses side
            // by side; the shell is only their container.
            GlassEffectContainer(spacing: paletteContainerSpacing) { content }
        case .panel(.hints(let dimmed)):
            // Lingering fades the content only; the glass stays at full strength.
            content.opacity(dimmed ? hintsDimmedOpacity : 1).animation(.easeOut(duration: 0.15), value: dimmed)
                .glassEffect(.regular, in: panelShape(.hints(dimmed: dimmed)))
        case .panel(let kind):
            content.glassEffect(.regular, in: panelShape(kind))
        case .card(let state, let slide):
            let shape = RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
            content
                .background(SlidingFill(shape: shape, opacity: state == .selected ? 0.16 : state == .hover ? 0.06 : 0,
                                        slide: state == .selected && !reduceMotion ? slide : nil))
                .overlay(shape.strokeBorder(Color.accentColor, lineWidth: strong && state == .selected ? 2 : 0))
                .contentShape(shape)
                .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: state)
        case .well:
            let shape = RoundedRectangle(cornerRadius: wellRadius, style: .continuous)
            content.background(Color.primary.opacity(0.05), in: shape).clipShape(shape)
        case .field(let band):
            content.frame(height: band - fieldGap)
                .glassEffect(.regular, in: Capsule())
                .frame(height: band, alignment: .top)   // the band keeps its height; PaletteLayout stays
        case .results:
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: resultsRadius, style: .continuous))
        case .selection(let on):
            // The system selection colour with white text, as menus and Spotlight do; no
            // animation, it jumps like a menu.
            content
                .environment(\.backgroundProminence, on ? .increased : .standard)
                .foregroundStyle(on ? AnyShapeStyle(Color(nsColor: .alternateSelectedControlTextColor)) : AnyShapeStyle(.primary))
                .background(on ? Color(nsColor: .selectedContentBackgroundColor) : .clear,
                            in: RoundedRectangle(cornerRadius: rowRadius, style: .continuous))
        case .chip(let size):
            // Key caps sit on glass, so they are flat, in classic's ink. `Color.opacity` makes a
            // plain colour; a faded foreground style is vibrant on glass instead, where a 0.1 fill
            // darkens it by 2% rather than 8% and the cap all but vanishes. On a selected row the
            // plain colour still turns white with the text.
            let shape = RoundedRectangle(cornerRadius: chipRadius(size), style: .continuous)
            content.background(shape.fill(Color.primary.opacity(chipFill(strong: strong))))
                .overlay(shape.strokeBorder(Color.primary.opacity(chipStroke(strong: strong)), lineWidth: chipStrokeWidth))
        case .label:
            content.foregroundStyle(.primary)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))   // a capsule on one line
        case .scrim:
            content.background(Color.black.opacity(0.12))
        case .tab(.incoming):
            content.background(Capsule().fill(Color.accentColor.opacity(tabIncomingFill)))
                .overlay(Capsule().strokeBorder(Color.accentColor,
                                                style: StrokeStyle(lineWidth: tabIncomingStrokeWidth(strong: strong),
                                                                   dash: tabIncomingDash)))
        case .dropTarget(let kind):
            content.overlay(dropRing(kind, width: dropRingWidth(strong: strong)))
        case .tab(let state):
            content
                .background(Capsule().fill(Color.primary.opacity(state == .active ? 0.14 : state == .hover ? 0.06 : 0))
                    .animation(reduceMotion ? nil : .smooth(duration: 0.12), value: state))   // only the fill moves
                .overlay(Capsule().strokeBorder(Color.accentColor, lineWidth: strong && state == .active ? 2 : 0))
        }
    }

    @ViewBuilder
    static func control(_ kind: OverlayControlKind, _ configuration: PrimitiveButtonStyleConfiguration) -> some View {
        switch kind {
        case .card:
            // In the card's header, on the shell's glass: glass on glass turns grey, so a flat circle.
            Button(action: configuration.trigger) { configuration.label }.buttonStyle(FillControlStyle(side: 18))
        case .tabClose:
            Button(action: configuration.trigger) { configuration.label }.buttonStyle(FillControlStyle(side: 16))
        }
    }
}

/// A small button sitting on glass: a flat circle, with the pressed state classic lacks.
struct FillControlStyle: ButtonStyle {
    let side: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        FilledCircle(side: side, label: configuration.label, isPressed: configuration.isPressed)
    }

    private struct FilledCircle: View {
        let side: CGFloat
        let label: ButtonStyleConfiguration.Label
        let isPressed: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            label.font(.system(size: 9, weight: .bold))
                .frame(width: side, height: side)
                .background(Circle().fill(Color.primary.opacity(isPressed ? 0.22 : 0.10)))
                .contentShape(Circle())
                .scaleEffect(isPressed && !reduceMotion ? 0.9 : 1)
                .animation(.snappy(duration: 0.12), value: isPressed)
        }
    }
}

/// The selection fill; with `slide` it slides from card to card with matchedGeometryEffect.
/// Only the fill moves, never the card.
struct SlidingFill: View {
    let shape: RoundedRectangle
    let opacity: Double
    let slide: Namespace.ID?

    var body: some View {
        if let slide {
            shape.fill(Color.primary.opacity(opacity)).matchedGeometryEffect(id: "selection", in: slide)
        } else {
            shape.fill(Color.primary.opacity(opacity))
        }
    }
}
