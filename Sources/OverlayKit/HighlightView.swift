import SwiftUI

/// A translucent rounded highlight, used by the window picker. Its corners, fill and stroke are
/// the skin's zone style, the same as a snap zone's.
public struct HighlightView: View {
    public var tint: Color
    @Environment(\.skin) private var skin

    public init(tint: Color = .accentColor) {
        self.tint = tint
    }

    public var body: some View {
        let zone = ZoneStyles.of(skin).zone
        let shape = RoundedRectangle(cornerRadius: zone.cornerRadius, style: .continuous)
        shape.fill(tint.opacity(zone.fillOpacity))
            .overlay(shape.strokeBorder(tint.opacity(zone.strokeOpacity), lineWidth: zone.lineWidth))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Covers one display (`canvas`, global coordinates) and draws a `HighlightView` at `target`,
/// sliding when the target changes. Host it in a pass-through panel over that display.
public struct HighlightLayer: View {
    public var target: CGRect?
    public var canvas: CGRect
    public var tint: Color

    public init(target: CGRect?, canvas: CGRect, tint: Color = .accentColor) {
        self.target = target
        self.canvas = canvas
        self.tint = tint
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            if let local = Self.localTarget(target, in: canvas) {
                HighlightView(tint: tint)
                    .frame(width: local.width, height: local.height)
                    .offset(x: local.minX, y: local.minY)
            }
        }
        .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
        .clipped()
        .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.88), value: target)
        .allowsHitTesting(false)
    }

    /// The part of `target` to draw on `canvas`, in the canvas's own coordinates.
    static func localTarget(_ target: CGRect?, in canvas: CGRect) -> CGRect? {
        guard let target, target.intersects(canvas) else { return nil }
        return OverlayGeometry.localFrame(of: target, in: canvas)
    }
}
