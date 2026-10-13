import CoreKit
import Contracts

/// "左半屏", "右上" and so on for the app list; "自定义区域" for anything else.
enum ZoneName {
    static var custom: String { L10n.text("workspaces.custom.area") }
    /// Gaps between windows and a tab bar shift a frame by a few percent of the screen.
    private static let tolerance = 0.045

    static func name(for rect: UnitRect) -> String {
        guard [rect.x, rect.y, rect.width, rect.height].allSatisfy(\.isFinite) else { return custom }
        return zones.first { near(rect, $0.rect) }?.name ?? custom
    }

    private static let zones: [(rect: UnitRect, name: String)] = {
        let third = 1.0 / 3
        return [
            (.full, L10n.text("workspaces.entire.screen")),
            (UnitRect(x: 0, y: 0, width: 0.5, height: 1), L10n.text("overlaykit.left.half")),
            (UnitRect(x: 0.5, y: 0, width: 0.5, height: 1), L10n.text("windowlayout.right.half")),
            (UnitRect(x: 0, y: 0, width: 1, height: 0.5), L10n.text("windowlayout.top.half")),
            (UnitRect(x: 0, y: 0.5, width: 1, height: 0.5), L10n.text("windowlayout.bottom.half")),
            (UnitRect(x: 0, y: 0, width: 0.5, height: 0.5), L10n.text("workspaces.top.left")),
            (UnitRect(x: 0.5, y: 0, width: 0.5, height: 0.5), L10n.text("workspaces.top.right")),
            (UnitRect(x: 0, y: 0.5, width: 0.5, height: 0.5), L10n.text("workspaces.bottom.left")),
            (UnitRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5), L10n.text("workspaces.bottom.right")),
            (UnitRect(x: 0, y: 0, width: third, height: 1), L10n.text("workspaces.left.third")),
            (UnitRect(x: third, y: 0, width: third, height: 1), L10n.text("workspaces.middle.third")),
            (UnitRect(x: 2 * third, y: 0, width: third, height: 1), L10n.text("workspaces.right.third")),
            (UnitRect(x: 0, y: 0, width: 2 * third, height: 1), L10n.text("workspaces.left.two.thirds")),
            (UnitRect(x: third, y: 0, width: 2 * third, height: 1), L10n.text("workspaces.right.two.thirds")),
        ]
    }()

    /// All four edges within the tolerance.
    private static func near(_ a: UnitRect, _ b: UnitRect) -> Bool {
        abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
            && abs(a.x + a.width - b.x - b.width) <= tolerance && abs(a.y + a.height - b.y - b.height) <= tolerance
    }
}
