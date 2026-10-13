import AppKit
import CoreKit
import OverlayKit
import QuartzCore

/// Draws the snap preview with Core Animation over the display it covers: one layer per zone,
/// so a new zone fades in on its own while the old one fades out where it was, and a first
/// zone grows out of the dragged window. Frames come in global coordinates.
///
/// A zone is a stroked layer, or a view of real glass whose layer is animated the same way;
/// OverlayKit decides which and hands over a `ZoneSurface`. The grid is always stroked layers.
@MainActor
final class SnapPreviewLayerView: NSView {
    /// How long a zone takes to appear, growing out of the window or fading in.
    static let appearDuration: CFTimeInterval = 0.16
    static let crossfadeDuration: CFTimeInterval = 0.12
    static let fadeOutDuration: CFTimeInterval = 0.10
    /// How opaque a zone is as it starts growing out of the window.
    static let growOpacity: Float = 0.35

    /// How the zone and grid cells are painted. The presenter sets this before every `show`
    /// (Liquid Glass skin design 3.2, 6.3 task 6); only its colors, radii and line widths come
    /// from here, never its geometry.
    var zones = ZoneStyles.current
    /// From the layout settings, "吸附预览用玻璃": a new zone is real glass where the skin has a
    /// glass zone. The presenter sets this before every `show`, like `zones`; a view nobody has
    /// told stays stroked.
    var prefersGlass = false

    /// The zone on screen, and the grid under it while the grid shows.
    private(set) var zone: CALayer?
    private(set) var grid: CALayer?
    /// Layers still fading out. An instant change removes them at once, so emptying the
    /// overlay before it moves to another display leaves nothing behind.
    private(set) var fading: [CALayer] = []
    /// What shows `zone` and each zone in `fading`, by its layer: a glass zone is a view and has
    /// to leave as one. The grid's layer is not in here.
    private var surfaces: [ObjectIdentifier: ZoneSurface] = [:]
    /// The target `zone` shows, global, as the preview gave it. Compared as given: a layer's
    /// frame is worked out from its position and bounds and need not read back exactly.
    private var zoneTarget: CGRect?
    private var gridCells: [CGRect]?
    /// The display the overlay covers, global; layers are placed relative to it.
    private var canvas = CGRect.zero

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// Shows `preview`, or nothing, the way `change` says. `completion` runs exactly once: right
    /// away for an instant or unchanged change, otherwise once Core Animation has finished or
    /// dropped the change's animations. Only an instant change drops the fade of a layer that
    /// left; a later change drops the animations of the zone or grid it replaces.
    func apply(_ preview: SnapPreview?, change: SnapPreviewChange, completion: @escaping () -> Void = {}) {
        guard let root = layer else { return completion() }
        if let preview { canvas = preview.canvas }
        switch change {
        case .unchanged:
            completion()
        case .instant:
            transition(to: preview, in: root, duration: 0, timing: .linear, completion: completion)
        case .grow(let origin):
            transition(to: preview, in: root, duration: Self.appearDuration, timing: .easeOut, growFrom: origin,
                       completion: completion)
        case .fadeIn:
            transition(to: preview, in: root, duration: Self.appearDuration, timing: .easeOut,
                       completion: completion)
        case .crossfade:
            transition(to: preview, in: root, duration: Self.crossfadeDuration, timing: .easeOut,
                       completion: completion)
        case .fadeOut:
            transition(to: nil, in: root, duration: Self.fadeOutDuration, timing: .easeIn, completion: completion)
        }
    }

    /// Puts the new zone, and the grid when its cells changed, in place and fades out the old
    /// ones over `duration`; 0 switches at once. A zone showing the same target is kept as it is
    /// when only the grid changes; a grow always starts a new zone.
    private func transition(to preview: SnapPreview?, in root: CALayer, duration: CFTimeInterval,
                            timing: CAMediaTimingFunctionName, growFrom origin: CGRect? = nil,
                            completion: @escaping () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        var leaving: [CALayer] = []
        var entering: [CALayer] = []
        let keepsZone = origin == nil && preview != nil && preview?.target == zoneTarget
        if !keepsZone {
            if let old = zone { leaving.append(old) }
            zoneTarget = preview?.target
            let surface = preview.map { zones.snapZone(frame: local($0.target), prefersGlass: prefersGlass) }
            zone = surface?.layer
            if let surface {
                surface.add(to: self)
                surfaces[ObjectIdentifier(surface.layer)] = surface
                entering.append(surface.layer)
            }
        }
        if preview?.gridCells != gridCells {
            if let old = grid { leaving.append(old) }
            gridCells = preview?.gridCells
            grid = gridCells.map { gridLayer(cells: $0.map(local), size: root.bounds.size) }
            if let grid {
                root.insertSublayer(grid, at: 0)
                entering.append(grid)
            }
        }
        guard duration > 0 else {
            (fading + leaving).forEach(remove)
            fading = []
            return completion()
        }
        // Runs once the animations added below are over or dropped. They start when the transaction
        // is committed, which can be later than this call, so a timer started here could cut them short.
        CATransaction.setCompletionBlock { [weak self] in
            // Without the view, its layers and glass are off the screen already.
            for layer in leaving { self?.remove(layer) }
            self?.fading.removeAll { layer in leaving.contains { $0 === layer } }
            completion()
        }
        for layer in leaving {
            // Leave from wherever it shows now, even mid-animation: no jump, no further travel.
            let opacity = Self.settle(layer)
            layer.opacity = 0
            Self.animate(layer, "opacity", from: opacity, to: Float(0), duration: duration, timing: timing)
        }
        fading += leaving
        for layer in entering {
            if layer === zone, let origin, let surface = surfaces[ObjectIdentifier(layer)] {
                // Out of the window: from its frame to the target, from faint to full. The surface
                // says how: a stroked layer changes its size, glass is scaled.
                for step in surface.growth(from: local(origin)) {
                    Self.animate(layer, step.keyPath, from: step.from, to: step.to, duration: duration, timing: timing)
                }
                Self.animate(layer, "opacity", from: Self.growOpacity, to: Float(1), duration: duration, timing: timing)
            } else {
                Self.animate(layer, "opacity", from: Float(0), to: Float(1), duration: duration, timing: timing)
            }
        }
    }

    private func local(_ rect: CGRect) -> CGRect {
        OverlayGeometry.localFrame(of: rect, in: canvas)
    }

    /// Takes a layer that has left off the screen; a glass zone's layer goes with its view.
    private func remove(_ layer: CALayer) {
        if let surface = surfaces.removeValue(forKey: ObjectIdentifier(layer)) {
            surface.remove()
        } else {
            layer.removeFromSuperlayer()
        }
    }

    /// Stops `layer` where it shows now, dropping its animations, and returns its opacity there.
    /// A growing glass zone is scaled rather than resized, so its transform stops too.
    private static func settle(_ layer: CALayer) -> Float {
        if let shown = layer.presentation() {
            layer.position = shown.position
            layer.bounds = shown.bounds
            layer.transform = shown.transform
            layer.opacity = shown.opacity
        }
        layer.removeAllAnimations()
        return layer.opacity
    }

    private static func animate(_ layer: CALayer, _ keyPath: String, from: Any, to: Any,
                                duration: CFTimeInterval, timing: CAMediaTimingFunctionName) {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: timing)
        layer.add(animation, forKey: keyPath)
    }

    /// Faint cells under the highlight while the grid shows. The inset is geometry and stays
    /// here; the per-cell paint comes from `zones.gridCell`.
    private func gridLayer(cells: [CGRect], size: CGSize) -> CALayer {
        let container = CALayer()
        container.frame = CGRect(origin: .zero, size: size)
        for cell in cells {
            container.addSublayer(zones.gridCell.layer(frame: RectMath.inset(cell, by: 3)))
        }
        return container
    }
}
