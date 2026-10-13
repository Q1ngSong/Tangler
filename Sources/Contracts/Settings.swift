import Foundation

/// One module's settings. Stored as {"version": N, "payload": {...}} by `SettingsCodec`.
/// Bump `version` and extend `migrate` whenever the stored shape changes, and add a
/// sample of the old version under Tests/Fixtures/settings/<moduleID>/ (design section 6).
public protocol ModuleSettings: Codable, Equatable, Sendable {
    static var moduleID: ModuleID { get }
    static var version: Int { get }
    static var defaultValue: Self { get }
    /// Converts a payload saved by an older `version` into the current version's JSON.
    static func migrate(from version: Int, json: Data) throws -> Data
}

public extension ModuleSettings {
    static func migrate(from version: Int, json: Data) throws -> Data {
        throw SettingsError.unsupportedVersion(module: moduleID, version: version)
    }
}

public enum SettingsError: Error, Equatable, Sendable {
    case unsupportedVersion(module: ModuleID, version: Int)
    case corrupted(module: ModuleID)
}

/// Implemented by SettingsKit; stores every module's settings separately.
public protocol SettingsStore: AnyObject, Sendable {
    /// The stored value, migrated if needed, or `defaultValue` when missing or unreadable.
    func load<S: ModuleSettings>(_ type: S.Type) -> S
    func save<S: ModuleSettings>(_ value: S)
    /// A new stream for each caller with every value saved afterwards.
    func changes<S: ModuleSettings>(_ type: S.Type) -> AsyncStream<S>
}

/// The storage format shared by every SettingsStore implementation and the fixtures.
public enum SettingsCodec {
    public static func encode<S: ModuleSettings>(_ value: S) throws -> Data {
        let payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: .fragmentsAllowed)
        return try JSONSerialization.data(withJSONObject: ["version": S.version, "payload": payload],
                                          options: [.sortedKeys])
    }

    /// The version `data` was stored with; nil when it is not in this format.
    public static func storedVersion(of data: Data) -> Int? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["version"] as? Int
    }

    public static func decode<S: ModuleSettings>(_ type: S.Type, from data: Data) throws -> S {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["version"] as? Int, let payload = object["payload"],
              let raw = try? JSONSerialization.data(withJSONObject: payload, options: .fragmentsAllowed) else {
            throw SettingsError.corrupted(module: S.moduleID)
        }
        let current = version == S.version ? raw : try S.migrate(from: version, json: raw)
        do {
            return try JSONDecoder().decode(S.self, from: current)
        } catch {
            throw SettingsError.corrupted(module: S.moduleID)
        }
    }
}
