import Contracts
import CoreGraphics
import OverlayKit

/// Sizes of the preview panel, worked out from the windows so the panel can be placed and
/// tested without measuring SwiftUI. Cards run along the Dock: in a row above a bottom Dock,
/// in a column beside a side Dock. A strip longer than the display scrolls.
struct DockPreviewLayout: Equatable {
    enum Axis: Equatable {
        case horizontal, vertical
    }

    static let previewHeight = ThumbnailCardLayout.defaultPreviewHeight
    static let padding: CGFloat = 8
    static let spacing: CGFloat = 6
    static let noticeHeight: CGFloat = 16
    /// Keeps the panel off the edges of the visible area.
    static let margin: CGFloat = 8

    let axis: Axis
    let cardSizes: [CGSize]
    /// The visible part of the card strip.
    let stripSize: CGSize
    /// The whole strip along the axis; longer than the visible part when it scrolls.
    let contentLength: CGFloat
    let panelSize: CGSize

    var scrolls: Bool { contentLength > (axis == .horizontal ? stripSize.width : stripSize.height) }

    /// Thumbnails are captured at twice the size their card shows them, for Retina displays.
    static func thumbnailPixelSize(for windowSize: CGSize) -> Int {
        let width = ThumbnailCardLayout.previewWidth(for: windowSize, previewHeight: previewHeight)
        return Int((2 * max(width, previewHeight)).rounded(.up))
    }

    /// `area` is the size of the visible area the panel must fit in.
    init(windowSizes: [CGSize], dockEdge: ScreenEdge, noticeCount: Int, area: CGSize) {
        axis = dockEdge == .left || dockEdge == .right ? .vertical : .horizontal
        let cardHeight = ThumbnailCardLayout.cardHeight(previewHeight: Self.previewHeight)
        cardSizes = windowSizes.map {
            CGSize(width: ThumbnailCardLayout.cardWidth(for: $0, previewHeight: Self.previewHeight), height: cardHeight)
        }
        let gaps = Self.spacing * CGFloat(max(0, cardSizes.count - 1))
        let notices = noticeCount > 0 ? Self.spacing + CGFloat(noticeCount) * Self.noticeHeight : 0
        let inset = 2 * (Self.margin + Self.padding)
        let room = CGSize(width: max(0, area.width - inset), height: max(0, area.height - inset - notices))
        let widest = cardSizes.map(\.width).max() ?? 0
        switch axis {
        case .horizontal:
            contentLength = cardSizes.map(\.width).reduce(0, +) + gaps
            stripSize = CGSize(width: min(contentLength, room.width), height: min(cardHeight, room.height))
        case .vertical:
            contentLength = cardSizes.map(\.height).reduce(0, +) + gaps
            stripSize = CGSize(width: min(widest, room.width), height: min(contentLength, room.height))
        }
        panelSize = CGSize(width: stripSize.width + 2 * Self.padding,
                           height: stripSize.height + notices + 2 * Self.padding)
    }
}
