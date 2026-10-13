import Contracts
import Foundation

/// Version 1 saved windows wherever they were; version 2 saves entries of one desktop
/// (workspaces design, section 4); version 3 adds the automatic saving of checkpoints, on and
/// every 60 minutes; version 4 adds the template lock, off; version 5 adds the recycle bin, empty.
/// Works on the JSON so the old types need not be kept.
enum WorkspaceMigration {
    static func fromVersionFour(_ json: Data) throws -> Data {
        guard var payload = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw SettingsError.corrupted(module: WorkspaceSettings.moduleID)
        }
        payload["bin"] = [Any]()
        return try JSONSerialization.data(withJSONObject: payload)
    }

    static func fromVersionThree(_ json: Data) throws -> Data {
        guard var payload = try JSONSerialization.jsonObject(with: json) as? [String: Any],
              let workspaces = payload["workspaces"] as? [[String: Any]] else {
            throw SettingsError.corrupted(module: WorkspaceSettings.moduleID)
        }
        payload["workspaces"] = workspaces.map { $0.merging(["isLocked": false]) { old, _ in old } }
        return try JSONSerialization.data(withJSONObject: payload)
    }

    static func fromVersionTwo(_ json: Data) throws -> Data {
        guard var payload = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw SettingsError.corrupted(module: WorkspaceSettings.moduleID)
        }
        payload["autoSave"] = true
        // The default for those who never chose: what was stored since is kept as it is.
        payload["autoSaveMinutes"] = 60
        return try JSONSerialization.data(withJSONObject: payload)
    }

    static func fromVersionOne(_ json: Data) throws -> Data {
        guard var payload = try JSONSerialization.jsonObject(with: json) as? [String: Any],
              let workspaces = payload["workspaces"] as? [[String: Any]] else {
            throw SettingsError.corrupted(module: WorkspaceSettings.moduleID)
        }
        payload["workspaces"] = workspaces.map(workspace)
        return try JSONSerialization.data(withJSONObject: payload)
    }

    private static func workspace(_ old: [String: Any]) -> [String: Any] {
        var new = old
        new["savedAt"] = old["createdAt"]
        new["tabGroups"] = [Any]()
        new["windows"] = (old["windows"] as? [[String: Any]] ?? []).map(window)
        return new
    }

    private static func window(_ old: [String: Any]) -> [String: Any] {
        var new = old
        for key in ["space", "windowID", "pid", "documentURL", "reopen"] { new[key] = nil }
        let reopen = old["reopen"] as? [String: Any]
        new["contents"] = reopen.map { [$0] } ?? [Any]()
        let detected = ReopenTarget.detected(documentURL: (old["documentURL"] as? String).flatMap(URL.init(string:)))
        new["contentsAreCustom"] = target(reopen).map(withoutPrivate) != detected.map(withoutPrivate)
        new["windowing"] = Windowing.automatic.rawValue
        if let windowID = old["windowID"], let pid = old["pid"] {
            new["lastWindow"] = ["windowID": windowID, "pid": pid]
        }
        return new
    }

    private static func target(_ json: [String: Any]?) -> ReopenTarget? {
        guard let json, let kind = (json["kind"] as? String).flatMap(ReopenTarget.Kind.init(rawValue:)),
              let target = json["target"] as? String else { return nil }
        return ReopenTarget(kind: kind, target: target)
    }

    /// /private/tmp and /tmp are one folder, but a path is only standardized to the short form
    /// while its file exists: a document deleted since must not look like a manual edit.
    private static func withoutPrivate(_ target: ReopenTarget) -> ReopenTarget {
        let shortened = String(target.target.dropFirst("/private".count))
        let aliased = ["/tmp", "/var", "/etc"].contains { shortened == $0 || shortened.hasPrefix($0 + "/") }
        return target.target.hasPrefix("/private/") && aliased ? ReopenTarget(kind: target.kind, target: shortened) : target
    }
}
