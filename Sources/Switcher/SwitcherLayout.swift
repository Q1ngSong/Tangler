import Contracts
import CoreGraphics
import OverlayKit

/// Sizes and position of the switcher panel, in global coordinates.
enum SwitcherLayout {
    static let cardSpacing: CGFloat = 8
    /// Around the cards, inside the panel.
    static let stripPadding: CGFloat = 10
    /// Kept free between the panel and the display's edges.
    static let screenMargin: CGFloat = 40
    /// Thumbnails are captured for Retina displays.
    static let backingScale: CGFloat = 2

    /// Every card side by side; the panel scrolls when this is wider than the display.
    static func stripWidth(for windows: [WindowInfo], previewHeight: CGFloat) -> CGFloat {
        let cards = windows.reduce(CGFloat(0)) { width, window in
            width + ThumbnailCardLayout.cardWidth(for: window.frame.size, previewHeight: previewHeight)
        }
        return cards + cardSpacing * CGFloat(max(windows.count - 1, 0)) + 2 * stripPadding
    }

    static func stripHeight(previewHeight: CGFloat) -> CGFloat {
        ThumbnailCardLayout.cardHeight(previewHeight: previewHeight) + 2 * stripPadding
    }

    /// The visible part of the display under the pointer, less a margin. A pointer outside
    /// every display, e.g. exactly on the bottom edge, goes to the nearest one.
    static func area(for pointer: CGPoint, in displays: [DisplayInfo]) -> CGRect? {
        let display = displays.first { $0.frame.contains(pointer) }
            ?? displays.min { distance(from: pointer, to: $0.frame) < distance(from: pointer, to: $1.frame) }
        return display?.visibleFrame.insetBy(dx: screenMargin, dy: screenMargin)
    }

    /// Long edge for thumbnails, enough for the widest preview a card shows.
    static func thumbnailPixelSize(previewHeight: CGFloat) -> Int {
        let widest = ThumbnailCardLayout.previewWidth(for: CGSize(width: 1_000_000, height: 1), previewHeight: previewHeight)
        return Int((max(widest, previewHeight) * backingScale).rounded(.up))
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
