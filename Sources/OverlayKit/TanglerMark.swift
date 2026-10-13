import AppKit
import SwiftUI

/// Four window tiles form the Tangler mark; the tilted tile is snapping into place.
public struct TanglerMark: View {
    public init() {}

    /// The status item shares the sidebar geometry; AppKit supplies the menu bar tint.
    public static func menuBarImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let path = TanglerMarkShape().path(in: CGRect(origin: .zero, size: size)).cgPath
        let image = NSImage(size: size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(path)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Tangler"
        return image
    }

    public var body: some View {
        TanglerMarkShape()
            .fill()
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
    }
}

private struct TanglerMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(in: CGRect(x: 60, y: 118, width: 66, height: 78),
                            cornerSize: CGSize(width: 15, height: 15))
        path.addRoundedRect(in: CGRect(x: 60, y: 60, width: 66, height: 46),
                            cornerSize: CGSize(width: 13, height: 13))
        path.addRoundedRect(in: CGRect(x: 138, y: 138, width: 58, height: 58),
                            cornerSize: CGSize(width: 14, height: 14))
        let arriving = Path(roundedRect: CGRect(x: 139, y: 59, width: 62, height: 62),
                            cornerRadius: 15)
        let rotation = CGAffineTransform(translationX: 170, y: 90)
            .rotated(by: .pi / 20)
            .translatedBy(x: -170, y: -90)
        path.addPath(arriving.applying(rotation))
        let scale = min(rect.width, rect.height) / 188
        return path.applying(CGAffineTransform(scaleX: scale, y: scale))
            .applying(CGAffineTransform(translationX: rect.midX - 128 * scale, y: rect.midY - 128 * scale))
    }
}
