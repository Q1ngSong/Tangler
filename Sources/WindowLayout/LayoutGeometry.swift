import CoreGraphics
import CoreKit

/// What a layout command does to the window's frame (design section 4.2).
enum LayoutAction: Equatable, CaseIterable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case maximize, center
}

enum LayoutGeometry {
    /// The share of the screen a repeated half command takes: 1/2 → 1/3 → 2/3, then again.
    static let cycle: [CGFloat] = [1.0 / 2, 1.0 / 3, 2.0 / 3]

    /// The frame `action` gives a window now at `window`, inside `bounds` (a display's visible
    /// frame) with `gap` points kept free around it.
    static func frame(for action: LayoutAction, window: CGRect, in bounds: CGRect, repeatIndex: Int,
                      gap: CGFloat) -> CGRect {
        let share = cycle[((repeatIndex % cycle.count) + cycle.count) % cycle.count]
        let width = bounds.width * share
        let height = bounds.height * share
        let rect: CGRect
        switch action {
        case .leftHalf: rect = CGRect(x: bounds.minX, y: bounds.minY, width: width, height: bounds.height)
        case .rightHalf: rect = CGRect(x: bounds.maxX - width, y: bounds.minY, width: width, height: bounds.height)
        case .topHalf: rect = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: height)
        case .bottomHalf: rect = CGRect(x: bounds.minX, y: bounds.maxY - height, width: bounds.width, height: height)
        case .topLeft: rect = EdgeSnap.topLeft.frame(in: bounds)
        case .topRight: rect = EdgeSnap.topRight.frame(in: bounds)
        case .bottomLeft: rect = EdgeSnap.bottomLeft.frame(in: bounds)
        case .bottomRight: rect = EdgeSnap.bottomRight.frame(in: bounds)
        case .maximize: rect = bounds
        case .center:
            let area = RectMath.inset(bounds, by: gap)
            let centered = CGRect(x: area.midX - window.width / 2, y: area.midY - window.height / 2,
                                  width: window.width, height: window.height)
            return rounded(RectMath.clamp(centered, to: area))
        }
        return rounded(RectMath.inset(rect, by: gap))
    }

    /// Rounds each edge rather than the size, so windows placed side by side share an edge
    /// and read-backs, which apps report in whole points, compare equal.
    static func rounded(_ rect: CGRect) -> CGRect {
        guard rect.isFiniteRect else { return rect }
        let minX = rect.minX.rounded(), minY = rect.minY.rounded()
        return CGRect(x: minX, y: minY, width: rect.maxX.rounded() - minX, height: rect.maxY.rounded() - minY)
    }
}
