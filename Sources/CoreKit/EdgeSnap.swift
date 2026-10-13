import CoreGraphics

/// Where a window lands when dragged to a screen edge without a modifier (design section 4.1).
public enum EdgeSnap: String, CaseIterable, Codable, Sendable {
    case leftHalf, rightHalf, topLeft, topRight, bottomLeft, bottomRight, maximize

    /// The target for a pointer at `point` on a display whose visible area is `bounds`.
    /// Corners win over edges. The bottom edge has no target because the Dock usually sits there.
    public static func target(for point: CGPoint, in bounds: CGRect, threshold: CGFloat = 24) -> EdgeSnap? {
        guard bounds.isFiniteRect, !bounds.isEmpty, point.x.isFinite, point.y.isFinite else { return nil }
        let threshold = threshold.isFinite ? max(0, threshold) : 24
        guard bounds.insetBy(dx: -threshold, dy: -threshold).contains(point) else { return nil }
        let left = point.x <= bounds.minX + threshold
        let right = point.x >= bounds.maxX - threshold
        let top = point.y <= bounds.minY + threshold
        let bottom = point.y >= bounds.maxY - threshold
        switch (top, bottom, left, right) {
        case (true, _, true, _): return .topLeft
        case (true, _, _, true): return .topRight
        case (_, true, true, _): return .bottomLeft
        case (_, true, _, true): return .bottomRight
        case (true, _, _, _): return .maximize
        case (_, _, true, _): return .leftHalf
        case (_, _, _, true): return .rightHalf
        default: return nil
        }
    }

    /// The frame this target occupies inside `bounds`.
    public func frame(in bounds: CGRect, gap: CGFloat = 0) -> CGRect {
        let halfWidth = bounds.width / 2
        let halfHeight = bounds.height / 2
        let rect: CGRect
        switch self {
        case .leftHalf: rect = CGRect(x: bounds.minX, y: bounds.minY, width: halfWidth, height: bounds.height)
        case .rightHalf: rect = CGRect(x: bounds.midX, y: bounds.minY, width: halfWidth, height: bounds.height)
        case .topLeft: rect = CGRect(x: bounds.minX, y: bounds.minY, width: halfWidth, height: halfHeight)
        case .topRight: rect = CGRect(x: bounds.midX, y: bounds.minY, width: halfWidth, height: halfHeight)
        case .bottomLeft: rect = CGRect(x: bounds.minX, y: bounds.midY, width: halfWidth, height: halfHeight)
        case .bottomRight: rect = CGRect(x: bounds.midX, y: bounds.midY, width: halfWidth, height: halfHeight)
        case .maximize: rect = bounds
        }
        return RectMath.inset(rect, by: gap)
    }
}
