import CoreGraphics

/// Where the tabs of a bar sit, in the bar's own coordinates (tab groups design 4.3): equal
/// widths from the left, at most `maxTabWidth`; too many tabs keep `minTabWidth` and overflow.
struct TabBarLayout: Equatable {
    static let padding: CGFloat = 6
    static let spacing: CGFloat = 4
    static let maxTabWidth: CGFloat = 220
    static let minTabWidth: CGFloat = 32
    /// Narrower tabs show their icon only.
    static let titleWidth: CGFloat = 80

    let barWidth: CGFloat
    let count: Int
    let tabWidth: CGFloat

    init(barWidth: CGFloat, count: Int) {
        self.barWidth = max(0, barWidth)
        self.count = max(0, count)
        guard count > 0 else {
            tabWidth = 0
            return
        }
        let available = self.barWidth - Self.padding * 2 - Self.spacing * CGFloat(count - 1)
        tabWidth = min(Self.maxTabWidth, max(Self.minTabWidth, (available / CGFloat(count)).rounded(.down)))
    }

    var showsTitles: Bool { tabWidth >= Self.titleWidth }

    func minX(ofTab index: Int) -> CGFloat { Self.padding + CGFloat(index) * (tabWidth + Self.spacing) }

    /// The tab under `x`; nil in the padding, between tabs and after the last one.
    func tab(atX x: CGFloat) -> Int? {
        guard count > 0 else { return nil }
        let index = Int(((x - Self.padding) / (tabWidth + Self.spacing)).rounded(.down))
        guard index >= 0, index < count, x - minX(ofTab: index) < tabWidth else { return nil }
        return index
    }

    /// The slot a drop at `x` takes, when the bar is laid out with the dropped tab already
    /// counted. That layout does not depend on where the tab goes, so the answer stays put
    /// while the other tabs make room. The gap before a slot belongs to it; left of the first
    /// slot is 0 and right of the last is `count - 1`.
    func slot(atX x: CGFloat) -> Int {
        guard count > 0 else { return 0 }
        let index = Int(((x - Self.padding + Self.spacing / 2) / (tabWidth + Self.spacing)).rounded(.down))
        return min(max(index, 0), count - 1)
    }
}
