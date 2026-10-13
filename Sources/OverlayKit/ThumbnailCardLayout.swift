import Contracts
import CoreGraphics

/// Sizes of a `ThumbnailCard`, so a strip of cards can be measured before it is shown.
public enum ThumbnailCardLayout {
    public static let defaultPreviewHeight: CGFloat = 140
    public static let padding: CGFloat = 7
    public static let headerHeight: CGFloat = 20
    public static let spacing: CGFloat = 6

    /// Windows wider or taller than this are letterboxed, so one window cannot squeeze the strip.
    static let aspectRange: ClosedRange<CGFloat> = 0.75...1.8
    static let defaultAspect: CGFloat = 1.6
    /// Leaves room for the title and the hover buttons.
    static let minimumPreviewWidth: CGFloat = 120

    /// Width of the preview area for a window of `windowSize`.
    public static func previewWidth(for windowSize: CGSize?, previewHeight: CGFloat) -> CGFloat {
        var aspect = defaultAspect
        if let size = windowSize, size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite {
            aspect = min(max(size.width / size.height, aspectRange.lowerBound), aspectRange.upperBound)
        }
        return max(minimumPreviewWidth, (previewHeight * aspect).rounded())
    }

    public static func cardWidth(for windowSize: CGSize?, previewHeight: CGFloat) -> CGFloat {
        previewWidth(for: windowSize, previewHeight: previewHeight) + 2 * padding
    }

    public static func cardHeight(previewHeight: CGFloat) -> CGFloat {
        previewHeight + headerHeight + spacing + 2 * padding
    }

    /// The window's title, or the app name for untitled windows.
    public static func title(for window: WindowInfo) -> String {
        window.title.isEmpty ? window.appName : window.title
    }
}
