import CoreGraphics

/// How the overlay goes from the preview it shows to the next (snap preview animation design):
/// a preview appears growing out of the dragged window, another zone crossfades in place, and
/// nothing ever slides from one zone to another.
enum SnapPreviewChange: Equatable, Sendable {
    /// Nothing to do: the same zone, or nothing before and after.
    case unchanged
    /// Animation is off: switch at once.
    case instant
    /// Appear growing out of the dragged window's frame.
    case grow(from: CGRect)
    /// Appear in place, fading in: with Reduce Motion, or with the window's frame unknown.
    case fadeIn
    /// Another zone while one shows: the new one fades in where it belongs as the old fades out.
    case crossfade
    /// Nothing next while one shows: it fades out where it is.
    case fadeOut

    /// `shown` is what the overlay shows now, `next` what it should show. Animation being off
    /// wins over Reduce Motion, which only turns a grow into a fade-in.
    static func between(_ shown: SnapPreview?, and next: SnapPreview?, animates: Bool,
                        reduceMotion: Bool) -> SnapPreviewChange {
        guard let next else {
            guard shown != nil else { return .unchanged }
            return animates ? .fadeOut : .instant
        }
        // Appearing, the first time or on another display (the panel moves there empty).
        guard let shown, shown.canvas == next.canvas else {
            guard animates else { return .instant }
            guard !reduceMotion, let origin = next.origin else { return .fadeIn }
            return .grow(from: origin)
        }
        guard shown != next else { return .unchanged }
        return animates ? .crossfade : .instant
    }
}
