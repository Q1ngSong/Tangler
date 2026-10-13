import AppKit
import QuartzCore

/// How a snap zone, a picker highlight or a grid cell is drawn. SwiftUI and Core Animation
/// share it. Feature modules see `ZoneStyles`, never the skin behind it (Liquid Glass skin
/// design 3.3).
public struct ZoneStyle: Equatable, Sendable {
    public var cornerRadius: CGFloat
    public var fillOpacity: CGFloat
    public var strokeOpacity: CGFloat
    public var lineWidth: CGFloat

    public init(cornerRadius: CGFloat, fillOpacity: CGFloat, strokeOpacity: CGFloat, lineWidth: CGFloat) {
        self.cornerRadius = cornerRadius
        self.fillOpacity = fillOpacity
        self.strokeOpacity = strokeOpacity
        self.lineWidth = lineWidth
    }

    /// A layer in this style at `frame`. The accent is NSColor.controlAccentColor, as HighlightView uses.
    @MainActor
    public func layer(frame: CGRect) -> CALayer {
        let layer = CALayer()
        layer.frame = frame
        paint(layer)
        return layer
    }

    /// Gives `layer` this style's corners, fill and stroke; a glass zone paints its content this way.
    @MainActor
    func paint(_ layer: CALayer) {
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        layer.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(fillOpacity).cgColor
        layer.borderColor = NSColor.controlAccentColor.withAlphaComponent(strokeOpacity).cgColor
        layer.borderWidth = lineWidth
    }
}

/// The zone styles of one skin.
public struct ZoneStyles: Equatable, Sendable {
    /// A snap zone or the window picker's highlight.
    public var zone: ZoneStyle
    /// The faint cells under a snap zone while the grid shows.
    public var gridCell: ZoneStyle
    /// The accent painted inside a snap zone made of real glass. Nil in a skin whose snap zones
    /// are only ever stroked, and in styles made without one.
    public var glassZone: ZoneStyle?

    public init(zone: ZoneStyle, gridCell: ZoneStyle, glassZone: ZoneStyle? = nil) {
        self.zone = zone
        self.gridCell = gridCell
        self.glassZone = glassZone
    }

    public static func of(_ skin: Skin) -> ZoneStyles {
        skin == .classic ? ClassicSkin.zones : LiquidGlassSkin.zones
    }

    /// The styles of the skin the user chose; read again for each new zone.
    @MainActor
    public static var current: ZoneStyles { of(CurrentSkin.shared.value) }

    /// What shows a snap zone at `frame`, in the coordinates of the view it will be added to:
    /// real glass when these styles have a glass zone and the user prefers it, otherwise the
    /// stroked `zone` layer. The caller passes only its own setting; which skin is in use, and
    /// so whether there is glass at all, is decided here.
    @MainActor
    public func snapZone(frame: CGRect, prefersGlass: Bool) -> ZoneSurface {
        if prefersGlass, let glassZone,
           let glass = ZoneSurface(view: LiquidGlassSkin.zoneGlass(accent: glassZone, frame: frame)) {
            return glass
        }
        return ZoneSurface(layer: zone.layer(frame: frame))
    }
}

/// What shows one snap zone: a stroked layer, or a view of real glass. Its owner adds it to a
/// view, animates `layer` and removes it, without knowing which of the two it has. The owner
/// may fade `layer` through its `opacity` either way; only growing differs, so `growth(from:)`
/// says which properties to animate.
@MainActor
public final class ZoneSurface {
    /// One property a growing zone animates, from its value at the start to its value at rest.
    public struct Step {
        public let keyPath: String
        public let from: NSValue
        public let to: NSValue
    }

    /// The layer that shows the zone, resting on the frame it was made for.
    public let layer: CALayer
    /// The glass. It is a view, so it joins and leaves its host as one.
    private let view: NSView?

    init(layer: CALayer) {
        self.layer = layer
        view = nil
    }

    /// Nil when `view` gives no layer to animate.
    init?(view: NSView) {
        view.wantsLayer = true
        guard let layer = view.layer else { return nil }
        self.layer = layer
        self.view = view
    }

    /// Whether the zone is real glass rather than a stroked layer. Owners have no need to know.
    var isGlass: Bool { view != nil }

    /// Puts the zone above everything `host` shows. `host` must be layer-backed.
    public func add(to host: NSView) {
        if let view {
            host.addSubview(view)
        } else {
            host.layer?.addSublayer(layer)
        }
    }

    /// Takes the zone out of the view it was added to.
    public func remove() {
        if let view {
            view.removeFromSuperview()
        } else {
            layer.removeFromSuperlayer()
        }
    }

    /// What to animate so the zone grows out of `start`, a frame in the coordinates of the frame
    /// the zone was made for, and ends where it rests. Ask after `add(to:)`.
    ///
    /// A stroked layer changes its size. Glass cannot: the layers that draw it are laid out for
    /// the size at rest and do not follow an animated size, so the glass would slide across at
    /// full size (seen in frames captured mid-animation in an off-screen window). It is scaled
    /// about its anchor instead, which those layers do follow.
    public func growth(from start: CGRect) -> [Step] {
        guard let view else {
            return [Step(keyPath: "position", from: NSValue(point: CGPoint(x: start.midX, y: start.midY)),
                         to: NSValue(point: layer.position)),
                    Step(keyPath: "bounds.size", from: NSValue(size: start.size), to: NSValue(size: layer.bounds.size))]
        }
        let rest = view.frame
        let anchor = layer.anchorPoint
        // Where the anchor is while the layer covers `start`, relative to where it is at rest.
        let from = CGPoint(x: layer.position.x + start.minX - rest.minX + anchor.x * (start.width - rest.width),
                           y: layer.position.y + start.minY - rest.minY + anchor.y * (start.height - rest.height))
        var steps = [Step(keyPath: "position", from: NSValue(point: from), to: NSValue(point: layer.position))]
        if rest.width > 0, rest.height > 0 {
            let scale = CATransform3DMakeScale(start.width / rest.width, start.height / rest.height, 1)
            steps.append(Step(keyPath: "transform", from: NSValue(caTransform3D: scale),
                              to: NSValue(caTransform3D: CATransform3DIdentity)))
        }
        return steps
    }
}
