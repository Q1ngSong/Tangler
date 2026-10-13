import Contracts
import Foundation

/// Settings of the Dock preview module (design section 4.4).
public struct DockPreviewSettings: ModuleSettings {
    public static let moduleID: ModuleID = "dock"
    public static let version = 3
    public static let defaultValue = DockPreviewSettings()

    static let showDelayRange: ClosedRange<Double> = 0.05...1
    static let dismissDelayRange: ClosedRange<Double> = 0.1...1

    /// Preview an app's windows while the pointer rests on its Dock icon.
    public var previewsEnabled: Bool
    /// Seconds the pointer rests on an icon before the preview opens.
    public var showDelay: Double
    /// Seconds after the pointer leaves both the icon and the preview before the preview closes.
    public var dismissDelay: Double
    public var showsSingleWindowApps: Bool
    public var clickBehavior: DockClickBehavior
    /// Keep pointer moves over the Dock from the Dock, so it shows no name labels; its
    /// magnification goes with them. Only while previews are on.
    public var hidesDockHover: Bool
    /// Fade the preview in and out, and glide it from icon to icon.
    public var animates: Bool

    /// The show delay defaults to 0.2 s: measured on the user's Mac, an app's windows and
    /// thumbnails are ready about 0.25 s into a hover, so waiting longer only adds lag.
    public init(previewsEnabled: Bool = true, showDelay: Double = 0.2, dismissDelay: Double = 0.2,
                showsSingleWindowApps: Bool = true, clickBehavior: DockClickBehavior = .systemDefault,
                hidesDockHover: Bool = false, animates: Bool = true) {
        self.previewsEnabled = previewsEnabled
        self.showDelay = showDelay
        self.dismissDelay = dismissDelay
        self.showsSingleWindowApps = showsSingleWindowApps
        self.clickBehavior = clickBehavior
        self.hidesDockHover = hidesDockHover
        self.animates = animates
    }

    /// Version 2 added `hidesDockHover`, off; version 3 adds `animates`, on.
    public static func migrate(from version: Int, json: Data) throws -> Data {
        guard version == 1 || version == 2 else {
            throw SettingsError.unsupportedVersion(module: moduleID, version: version)
        }
        guard var payload = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw SettingsError.corrupted(module: moduleID)
        }
        if version == 1 { payload["hidesDockHover"] = false }
        payload["animates"] = true
        return try JSONSerialization.data(withJSONObject: payload)
    }

    /// Hand-edited or corrupt delays fall back into range, so previews never flicker or never open.
    var effectiveShowDelay: Double {
        Self.clamp(showDelay, to: Self.showDelayRange, fallback: Self.defaultValue.showDelay)
    }

    var effectiveDismissDelay: Double {
        Self.clamp(dismissDelay, to: Self.dismissDelayRange, fallback: Self.defaultValue.dismissDelay)
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
    }
}
