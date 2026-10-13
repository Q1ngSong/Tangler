import CoreGraphics

/// The palette's size and place: a fixed width and as tall as its rows, up to eight, with the top
/// edge staying put while results change, so the search field never moves under the eyes.
enum PaletteLayout {
    static let width: CGFloat = 640
    static let fieldHeight: CGFloat = 52
    static let dividerHeight: CGFloat = 1
    static let rowHeight: CGFloat = 44
    static let listPadding: CGFloat = 6
    static let messageHeight: CGFloat = 30
    static let maxVisibleRows = 8

    /// An empty list still has one row, which says nothing matched.
    static func size(rows: Int, hasMessage: Bool) -> CGSize {
        let visible = CGFloat(min(max(rows, 1), maxVisibleRows))
        let list = listPadding * 2 + visible * rowHeight
        return CGSize(width: width, height: fieldHeight + dividerHeight + list + (hasMessage ? messageHeight : 0))
    }

    /// Centered across `area`, its top a fifth of the way down, kept inside `area`.
    static func frame(rows: Int, hasMessage: Bool, in area: CGRect) -> CGRect {
        let size = size(rows: rows, hasMessage: hasMessage)
        let width = max(0, min(size.width, area.width - 32))
        let top = (area.minY + area.height * 0.2).rounded()
        let height = max(0, min(size.height, area.maxY - 16 - top))
        return CGRect(x: (area.midX - width / 2).rounded(), y: top, width: width, height: height)
    }
}
