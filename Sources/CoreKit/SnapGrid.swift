import CoreGraphics

/// A cell in a snap grid, counted from the top-left corner.
public struct GridCell: Hashable, Sendable {
    public var column: Int
    public var row: Int

    public init(column: Int, row: Int) {
        self.column = column
        self.row = row
    }
}

/// The grid shown while dragging a window with the modifier held (design section 4.1).
/// Frames use global coordinates: origin at the top-left, y grows downward.
public struct SnapGrid: Hashable, Sendable {
    public let columns: Int
    public let rows: Int

    /// The default grid: 6 columns × 4 rows.
    public static let standard = SnapGrid(columns: 6, rows: 4)

    /// Values are clamped to 1...24 so a corrupt setting cannot produce an unusable grid.
    public init(columns: Int, rows: Int) {
        self.columns = min(max(columns, 1), 24)
        self.rows = min(max(rows, 1), 24)
    }

    /// The cell under `point`, or nil when the point lies outside `bounds`.
    public func cell(at point: CGPoint, in bounds: CGRect) -> GridCell? {
        guard bounds.isFiniteRect, !bounds.isEmpty, point.x.isFinite, point.y.isFinite,
              bounds.contains(point) else { return nil }
        let column = Int((point.x - bounds.minX) / bounds.width * CGFloat(columns))
        let row = Int((point.y - bounds.minY) / bounds.height * CGFloat(rows))
        return GridCell(column: min(column, columns - 1), row: min(row, rows - 1))
    }

    /// The frame of the rectangle whose opposite corner cells are `anchor` and `current`.
    public func frame(from anchor: GridCell, to current: GridCell, in bounds: CGRect, gap: CGFloat = 0) -> CGRect {
        let left = clampColumn(min(anchor.column, current.column))
        let right = clampColumn(max(anchor.column, current.column)) + 1
        let top = clampRow(min(anchor.row, current.row))
        let bottom = clampRow(max(anchor.row, current.row)) + 1
        let cellWidth = bounds.width / CGFloat(columns)
        let cellHeight = bounds.height / CGFloat(rows)
        let rect = CGRect(x: bounds.minX + CGFloat(left) * cellWidth, y: bounds.minY + CGFloat(top) * cellHeight,
                          width: CGFloat(right - left) * cellWidth, height: CGFloat(bottom - top) * cellHeight)
        return RectMath.inset(rect, by: gap)
    }

    /// Every cell's frame, row by row, for drawing the grid.
    public func cellFrames(in bounds: CGRect, gap: CGFloat = 0) -> [CGRect] {
        (0..<rows).flatMap { row in
            (0..<columns).map { column in
                let cell = GridCell(column: column, row: row)
                return frame(from: cell, to: cell, in: bounds, gap: gap)
            }
        }
    }

    private func clampColumn(_ column: Int) -> Int { min(max(column, 0), columns - 1) }
    private func clampRow(_ row: Int) -> Int { min(max(row, 0), rows - 1) }
}
