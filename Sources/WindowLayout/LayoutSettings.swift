import Contracts
import CoreGraphics
import CoreKit
import Foundation

/// The layout module's settings (batch 2 plan A.8). Stored values are kept as typed; the
/// derived properties clamp them, so a hand-edited or corrupt value cannot break a drag.
public struct LayoutSettings: ModuleSettings {
    public static let moduleID: ModuleID = "layout"
    public static let version = 3
    public static let defaultValue = LayoutSettings()

    /// Halves, quarters or the full screen when a window is dragged to a screen edge.
    public var edgeSnapping: Bool
    /// The grid while a window is dragged with `gridModifiers` held.
    public var grid: Bool
    public var gridModifiers: Modifiers
    public var gridColumns: Int
    public var gridRows: Int
    /// Points kept free around every placed window.
    public var gap: Double
    /// Seconds; 0 moves windows without animation.
    public var animationDuration: Double
    /// The snap zone is real glass rather than the stroked outline it is by default. Only the
    /// Liquid Glass skin has a glass zone; the classic skin ignores this.
    public var glassSnapPreview: Bool
    /// ⌃←, ⌃→ and ⌃digit switch desktops through Tangler, which does not wait for the system's
    /// animation. The system's own shortcuts for them have to be turned off by hand.
    public var handlesDesktopKeys: Bool

    public init(edgeSnapping: Bool = true, grid: Bool = true, gridModifiers: Modifiers = .option,
                gridColumns: Int = 6, gridRows: Int = 4, gap: Double = 0, animationDuration: Double = 0.18,
                glassSnapPreview: Bool = false, handlesDesktopKeys: Bool = false) {
        self.edgeSnapping = edgeSnapping
        self.grid = grid
        self.gridModifiers = gridModifiers
        self.gridColumns = gridColumns
        self.gridRows = gridRows
        self.gap = gap
        self.animationDuration = animationDuration
        self.glassSnapPreview = glassSnapPreview
        self.handlesDesktopKeys = handlesDesktopKeys
    }

    /// Version 2 adds `glassSnapPreview`, off: the zone stays stroked until the user asks for glass.
    /// Version 3 adds `handlesDesktopKeys`, off: the desktop shortcuts stay the system's.
    public static func migrate(from version: Int, json: Data) throws -> Data {
        guard version == 1 || version == 2 else {
            throw SettingsError.unsupportedVersion(module: moduleID, version: version)
        }
        guard var payload = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw SettingsError.corrupted(module: moduleID)
        }
        if version == 1 { payload["glassSnapPreview"] = false }
        payload["handlesDesktopKeys"] = false
        return try JSONSerialization.data(withJSONObject: payload)
    }

    var snapGrid: SnapGrid { SnapGrid(columns: gridColumns, rows: gridRows) }

    var gapPoints: CGFloat { gap.isFinite ? CGFloat(min(max(gap, 0), 64)) : 0 }

    var animation: FrameAnimation {
        guard animationDuration.isFinite, animationDuration > 0 else { return .none }
        return .animated(seconds: min(animationDuration, 1))
    }

    /// fn is ignored: macOS sets it on arrow keys and some mice whether or not it is held.
    func gridIsHeld(by modifiers: Modifiers) -> Bool {
        grid && !gridModifiers.isEmpty && modifiers.subtracting(.function).isSuperset(of: gridModifiers)
    }
}

extension LayoutSettings {
    private enum CodingKeys: String, CodingKey {
        case edgeSnapping, grid, gridModifiers, gridColumns, gridRows, gap, animationDuration, glassSnapPreview
        case handlesDesktopKeys
    }

    /// A missing field keeps its default instead of discarding every other setting.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = LayoutSettings()
        edgeSnapping = try container.decodeIfPresent(Bool.self, forKey: .edgeSnapping) ?? defaults.edgeSnapping
        grid = try container.decodeIfPresent(Bool.self, forKey: .grid) ?? defaults.grid
        gridModifiers = try container.decodeIfPresent(Modifiers.self, forKey: .gridModifiers) ?? defaults.gridModifiers
        gridColumns = try container.decodeIfPresent(Int.self, forKey: .gridColumns) ?? defaults.gridColumns
        gridRows = try container.decodeIfPresent(Int.self, forKey: .gridRows) ?? defaults.gridRows
        gap = try container.decodeIfPresent(Double.self, forKey: .gap) ?? defaults.gap
        animationDuration = try container.decodeIfPresent(Double.self, forKey: .animationDuration)
            ?? defaults.animationDuration
        glassSnapPreview = try container.decodeIfPresent(Bool.self, forKey: .glassSnapPreview)
            ?? defaults.glassSnapPreview
        handlesDesktopKeys = try container.decodeIfPresent(Bool.self, forKey: .handlesDesktopKeys)
            ?? defaults.handlesDesktopKeys
    }
}
