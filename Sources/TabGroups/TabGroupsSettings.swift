import Contracts
import CoreGraphics
import Foundation

/// Settings of the tab groups module (tab groups design 7).
public struct TabGroupsSettings: ModuleSettings {
    public static let moduleID: ModuleID = "tabs"
    public static let version = 1
    public static let defaultValue = TabGroupsSettings()

    static let barHeightRange: ClosedRange<Double> = 24...40

    /// Points the tab bar takes from the top of a group's area.
    public var barHeight: Double
    /// A window snapped exactly onto another window, or onto a group, merges with it.
    public var mergesOnSnap: Bool
    /// A window dragged with ⌘ held onto a tab bar joins that group.
    public var joinsByCommandDrag: Bool

    public init(barHeight: Double = 30, mergesOnSnap: Bool = true, joinsByCommandDrag: Bool = true) {
        self.barHeight = barHeight
        self.mergesOnSnap = mergesOnSnap
        self.joinsByCommandDrag = joinsByCommandDrag
    }

    /// A hand-edited or corrupt height falls back into range.
    var effectiveBarHeight: CGFloat {
        guard barHeight.isFinite else { return CGFloat(Self.defaultValue.barHeight) }
        return CGFloat(min(max(barHeight, Self.barHeightRange.lowerBound), Self.barHeightRange.upperBound))
    }
}

extension TabGroupsSettings {
    private enum CodingKeys: String, CodingKey {
        case barHeight, mergesOnSnap, joinsByCommandDrag
    }

    /// A missing field keeps its default instead of discarding every other setting.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = TabGroupsSettings()
        barHeight = try container.decodeIfPresent(Double.self, forKey: .barHeight) ?? defaults.barHeight
        mergesOnSnap = try container.decodeIfPresent(Bool.self, forKey: .mergesOnSnap) ?? defaults.mergesOnSnap
        joinsByCommandDrag = try container.decodeIfPresent(Bool.self, forKey: .joinsByCommandDrag)
            ?? defaults.joinsByCommandDrag
    }
}
