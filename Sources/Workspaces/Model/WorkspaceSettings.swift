import Contracts
import Foundation

/// Every saved workspace, stored as the module's settings (design section 4.5). The list
/// order is the leader key order: the first workspace is W 1, the tenth W 0.
struct WorkspaceSettings: ModuleSettings {
    static let moduleID = WorkspaceCommands.module
    static let version = 5
    static let defaultValue = WorkspaceSettings(workspaces: [])
    static let autoSaveMinutesRange = 1...120

    var workspaces: [Workspace]
    /// The recycle bin: deleted workspaces, each with its `deletedAt`, oldest first.
    var bin: [Workspace]
    /// Whether checkpoints are overwritten without being asked: every so often, when the
    /// workspace's desktop is left, on release and when Tangler quits.
    var autoSave: Bool
    /// Minutes between two automatic saves, within `autoSaveMinutesRange`.
    var autoSaveMinutes: Int

    init(workspaces: [Workspace], bin: [Workspace] = [], autoSave: Bool = true, autoSaveMinutes: Int = 60) {
        self.workspaces = workspaces
        self.bin = bin
        self.autoSave = autoSave
        self.autoSaveMinutes = Self.clamped(autoSaveMinutes)
    }

    /// Stored minutes outside the range are read as the nearest allowed value.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(workspaces: try container.decode([Workspace].self, forKey: .workspaces),
                  bin: try container.decode([Workspace].self, forKey: .bin),
                  autoSave: try container.decode(Bool.self, forKey: .autoSave),
                  autoSaveMinutes: try container.decode(Int.self, forKey: .autoSaveMinutes))
    }

    static func clamped(_ minutes: Int) -> Int {
        min(max(minutes, autoSaveMinutesRange.lowerBound), autoSaveMinutesRange.upperBound)
    }

    static func migrate(from version: Int, json: Data) throws -> Data {
        guard (1..<Self.version).contains(version) else {
            throw SettingsError.unsupportedVersion(module: moduleID, version: version)
        }
        // Each step takes the data one version on.
        var json = json
        if version <= 1 { json = try WorkspaceMigration.fromVersionOne(json) }
        if version <= 2 { json = try WorkspaceMigration.fromVersionTwo(json) }
        if version <= 3 { json = try WorkspaceMigration.fromVersionThree(json) }
        if version <= 4 { json = try WorkspaceMigration.fromVersionFour(json) }
        return json
    }
}
