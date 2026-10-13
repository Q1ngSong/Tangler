import Contracts
import CoreGraphics

/// The switcher's settings. Stored shape changes need a new `version`, a `migrate` step and
/// a sample under Tests/Fixtures/settings/switcher/.
struct SwitcherSettings: ModuleSettings {
    static let moduleID = SwitcherCommands.module
    static let version = 1
    static let defaultValue = SwitcherSettings()

    static let previewHeightRange: ClosedRange<Double> = 80...240

    var includeMinimized: Bool
    /// Height of each thumbnail in points.
    var previewHeight: Double

    init(includeMinimized: Bool = true, previewHeight: Double = 140) {
        self.includeMinimized = includeMinimized
        self.previewHeight = previewHeight
    }

    /// `previewHeight` kept in range, so a hand-edited value cannot break the layout.
    var effectivePreviewHeight: CGFloat {
        guard previewHeight.isFinite else { return CGFloat(Self.defaultValue.previewHeight) }
        return CGFloat(min(max(previewHeight, Self.previewHeightRange.lowerBound), Self.previewHeightRange.upperBound))
    }
}
