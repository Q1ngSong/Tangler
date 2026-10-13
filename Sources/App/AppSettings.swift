import CoreKit
import Contracts
import Foundation
import OverlayKit

/// Settings that belong to the App itself rather than to a module.
struct AppSettings: ModuleSettings {
    static let moduleID: ModuleID = "app"
    static let version = 3
    static let defaultValue = AppSettings(disabledModules: [], skin: .liquidGlass)

    /// Modules the user turned off. Stored this way round so new modules start by default.
    var disabledModules: Set<String>
    /// How Tangler draws its own interface. New in version 2.
    var skin: Skin
    /// Applied immediately and restored before app composition on the next launch.
    var language: AppLanguage = .system

    func isEnabled(_ module: ModuleID) -> Bool { !disabledModules.contains(module.rawValue) }

    /// Keep existing skins and module switches; older settings follow the system language.
    static func migrate(from version: Int, json: Data) throws -> Data {
        guard version == 1 || version == 2 else { throw SettingsError.unsupportedVersion(module: moduleID, version: version) }
        guard var payload = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw SettingsError.corrupted(module: moduleID)
        }
        if version == 1 { payload["skin"] = Skin.liquidGlass.rawValue }
        payload["language"] = AppLanguage.system.rawValue
        return try JSONSerialization.data(withJSONObject: payload)
    }
}
