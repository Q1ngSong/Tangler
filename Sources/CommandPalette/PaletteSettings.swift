import Contracts
import Foundation

/// The leader trigger, and how long leader mode stays after a command such as 左半屏 so a
/// repeat can cycle sizes (design section 4.2).
public struct PaletteSettings: ModuleSettings {
    public static let moduleID = PaletteCommands.module
    public static let version = 2
    public static let defaultValue = PaletteSettings()

    public var leaderTrigger: LeaderTrigger
    public var lingerSeconds: Double

    public init(leaderTrigger: LeaderTrigger = .holdRightCommand, lingerSeconds: Double = 1) {
        self.leaderTrigger = leaderTrigger
        self.lingerSeconds = lingerSeconds
    }

    /// Too short and a repeat cannot be typed in time; too long and the next typed text is swallowed.
    var effectiveLingerSeconds: Double { min(max(lingerSeconds, 0.3), 5) }

    /// Version 1 knew one way to use right Command, a tap within 0.3 s. Version 2 adds holding
    /// it, which is how right Command works by default, and turns 1's tap into that.
    public static func migrate(from version: Int, json: Data) throws -> Data {
        guard version == 1 else { throw SettingsError.unsupportedVersion(module: moduleID, version: version) }
        guard var payload = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw SettingsError.corrupted(module: moduleID)
        }
        if let trigger = payload["leaderTrigger"] as? [String: Any], trigger["tapRightCommand"] != nil {
            payload["leaderTrigger"] = ["holdRightCommand": [String: Any]()]
        }
        return try JSONSerialization.data(withJSONObject: payload)
    }
}
