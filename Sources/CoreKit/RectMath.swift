import CoreGraphics

public extension CGRect {
    /// False for null, infinite or NaN rectangles, which AppKit and AX occasionally report.
    var isFiniteRect: Bool {
        !isNull && !isInfinite && origin.x.isFinite && origin.y.isFinite && width.isFinite && height.isFinite
    }
}

public enum RectMath {
    /// Keeps as much of the requested size as fits, then moves the rectangle inside `bounds`.
    public static func clamp(_ rect: CGRect, to bounds: CGRect, minimumSize: CGSize = .zero) -> CGRect {
        guard bounds.isFiniteRect, !bounds.isEmpty else { return .zero }
        let minWidth = minimumSize.width.isFinite ? max(0, minimumSize.width) : 0
        let minHeight = minimumSize.height.isFinite ? max(0, minimumSize.height) : 0
        let requestedWidth = rect.width.isFinite ? abs(rect.width) : minWidth
        let requestedHeight = rect.height.isFinite ? abs(rect.height) : minHeight
        let width = min(bounds.width, max(minWidth, requestedWidth))
        let height = min(bounds.height, max(minHeight, requestedHeight))
        let x = rect.origin.x.isFinite ? rect.standardized.minX : bounds.minX
        let y = rect.origin.y.isFinite ? rect.standardized.minY : bounds.minY
        return CGRect(x: min(max(x, bounds.minX), bounds.maxX - width),
                      y: min(max(y, bounds.minY), bounds.maxY - height), width: width, height: height)
    }

    /// Shrinks every side by `amount`, never past the rectangle's center.
    public static func inset(_ rect: CGRect, by amount: CGFloat) -> CGRect {
        guard rect.isFiniteRect, !rect.isEmpty else { return .zero }
        let amount = amount.isFinite ? max(0, amount) : 0
        let dx = min(rect.width / 2, amount)
        let dy = min(rect.height / 2, amount)
        return CGRect(x: rect.minX + dx, y: rect.minY + dy,
                      width: max(0, rect.width - dx * 2), height: max(0, rect.height - dy * 2))
    }
}
