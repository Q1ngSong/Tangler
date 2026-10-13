import CoreKit
import Contracts
import Foundation
import Observation
import SwiftUI

/// The saved workspaces, kept in the module's settings. Every change is saved at once.
@MainActor
@Observable
final class WorkspaceLibrary {
    /// How long a deleted workspace stays in the recycle bin.
    static let binDays = 7

    private(set) var workspaces: [Workspace]
    /// The recycle bin as it is stored, which may hold workspaces whose time is up.
    private var binned: [Workspace]
    /// Whether checkpoints are saved without being asked. Change it through the controller,
    /// which starts and stops the saving.
    private(set) var autoSave: Bool
    private(set) var autoSaveMinutes: Int
    @ObservationIgnored private let settings: any SettingsStore
    @ObservationIgnored private let now: () -> Date

    init(settings: any SettingsStore, now: @escaping () -> Date = Date.init) {
        self.settings = settings
        self.now = now
        let stored = settings.load(WorkspaceSettings.self)
        workspaces = stored.workspaces
        binned = stored.bin
        autoSave = stored.autoSave
        autoSaveMinutes = stored.autoSaveMinutes
    }

    func setAutoSave(_ on: Bool) {
        guard on != autoSave else { return }
        autoSave = on
        persist()
    }

    /// Minutes outside the allowed range become the nearest allowed value.
    func setAutoSaveMinutes(_ minutes: Int) {
        let minutes = WorkspaceSettings.clamped(minutes)
        guard minutes != autoSaveMinutes else { return }
        autoSaveMinutes = minutes
        persist()
    }

    func workspace(id: UUID) -> Workspace? {
        workspaces.first { $0.id == id }
    }

    /// The workspace for the digit typed after W: 1…9 are the first nine, 0 the tenth.
    func workspace(forDigit digit: Int) -> Workspace? {
        let index = digit == 0 ? 9 : digit - 1
        return workspaces.indices.contains(index) ? workspaces[index] : nil
    }

    /// "W 1" for the first workspace; nil from the eleventh on, which only the palette reaches.
    func leaderKeys(for id: UUID) -> String? {
        guard let index = workspaces.firstIndex(where: { $0.id == id }), index < 10 else { return nil }
        return "W \((index + 1) % 10)"
    }

    /// Adds the workspace last, so the digits of the others stay the same.
    @discardableResult
    func create(windows: [SavedWindow], focused: UUID?, name: String = "", tabGroups: [SavedTabGroup] = [],
                screenAspect: Double? = nil) throws -> Workspace {
        guard !windows.isEmpty else { throw WorkspaceLibraryError.noWindows }
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let workspace = Workspace(id: UUID(), name: typed.isEmpty ? defaultName() : typed, createdAt: now(),
                                  windows: windows, tabGroups: tabGroups, savedAt: now(), screenAspect: screenAspect,
                                  options: WorkspaceOptions(launchesMissingApps: true, reopensMissingWindows: true,
                                                            focusedWindow: focused))
        workspaces.append(workspace)
        forget(Set(windows.compactMap(\.lastWindow)), except: workspace.id)
        persist()
        return workspace
    }

    /// A workspace with a name only; its first checkpoint is saved from its desktop.
    @discardableResult
    func createEmpty(name: String = "") -> Workspace {
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let workspace = Workspace(id: UUID(), name: typed.isEmpty ? defaultName() : typed, createdAt: now(), windows: [],
                                  options: WorkspaceOptions(launchesMissingApps: true, reopensMissingWindows: true))
        workspaces.append(workspace)
        persist()
        return workspace
    }

    /// Overwrites the workspace's checkpoint. An empty capture changes nothing. The entries in
    /// `keeping` stay when none of the captured windows is theirs; `groups` says what becomes of
    /// the saved tab groups the capture shows nothing of.
    @discardableResult
    func saveCheckpoint(_ id: UUID, captured: WindowCapture.Result, keeping: Set<UUID> = [],
                        groups: Checkpoint.Groups = .keepUnseen) throws -> Workspace {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { throw WorkspaceLibraryError.missingWorkspace }
        guard !captured.windows.isEmpty else { throw WorkspaceLibraryError.noWindows }
        workspaces[index] = Checkpoint.overwrite(workspaces[index], with: captured, at: now(), keeping: keeping,
                                                 groups: groups)
        forget(Set(workspaces[index].windows.compactMap(\.lastWindow)), except: id)
        persist()
        return workspaces[index]
    }

    /// Makes `desktop` the workspace's own. A desktop belongs to one workspace, so any other
    /// that had it lets go. A desktop without a UUID is refused: it could not be found again.
    func bind(_ id: UUID, to desktop: BoundDesktop) throws {
        guard !desktop.uuid.isEmpty else { throw WorkspaceLibraryError.unnamedDesktop }
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { throw WorkspaceLibraryError.missingWorkspace }
        for other in workspaces.indices where workspaces[other].desktop?.uuid == desktop.uuid {
            workspaces[other].desktop = nil
        }
        workspaces[index].desktop = desktop
        persist()
    }

    /// The workspace keeps its checkpoint; its desktop becomes an ordinary one.
    func unbind(_ id: UUID) throws {
        try change(id) { $0.desktop = nil }
    }

    /// Lets go of desktops that are no longer listed, as after the user removed one in Mission
    /// Control (workspaces design 6.5). Call it before a write. An empty list is one that could
    /// not be read, and drops nothing; nor does a display that is not listed, since disconnecting
    /// one hides its desktops without removing them.
    func dropStaleBindings(spaces: [SpaceInfo]) {
        guard !spaces.isEmpty else { return }
        let listed = Set(spaces.compactMap { WorkspaceDesktops.binding(for: $0)?.uuid })
        let displays = Set(spaces.map(\.displayID))
        let stale = workspaces.indices.filter { index in
            workspaces[index].desktop.map { displays.contains($0.displayID) && !listed.contains($0.uuid) } ?? false
        }
        guard !stale.isEmpty else { return }
        for index in stale { workspaces[index].desktop = nil }
        persist()
    }

    /// Returns the name as it is stored, trimmed.
    @discardableResult
    func rename(_ id: UUID, to name: String) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw WorkspaceLibraryError.emptyName }
        try change(id) { $0.name = name }
        return name
    }

    /// The workspace to select once `id` is removed: the one that takes its place, else the
    /// one before it.
    func neighbour(of id: UUID) -> UUID? {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return nil }
        if index + 1 < workspaces.count { return workspaces[index + 1].id }
        return index > 0 ? workspaces[index - 1].id : nil
    }

    // MARK: The recycle bin

    /// The deleted workspaces that can still be restored, oldest first. They are in no list of
    /// workspaces: no leader keys, no palette entry, no menu item, and nothing saves them.
    var bin: [Workspace] { binned.filter { !isExpired($0) } }

    /// The days until the deleted workspace is gone for good, counting the one that has begun.
    func daysLeft(for workspace: Workspace) -> Int {
        guard let deletedAt = workspace.deletedAt else { return Self.binDays }
        return max(1, Self.binDays - Int(now().timeIntervalSince(deletedAt) / Self.day))
    }

    /// Deletes the workspace into the bin. It is released first: its desktop stays as an ordinary
    /// one, and the windows its entries used are no longer remembered.
    func moveToBin(_ id: UUID) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        var workspace = workspaces.remove(at: index)
        workspace.desktop = nil
        workspace.deletedAt = now()
        for item in workspace.windows.indices { workspace.windows[item].lastWindow = nil }
        binned.append(workspace)
        dropExpired()
        persist()
    }

    /// Puts a deleted workspace back, last and not open.
    func restore(_ id: UUID) {
        guard var workspace = bin.first(where: { $0.id == id }) else { return }
        workspace.deletedAt = nil
        binned.removeAll { $0.id == id }
        workspaces.append(workspace)
        dropExpired()
        persist()
    }

    /// Deletes a workspace in the bin for good.
    func purge(_ id: UUID) {
        binned.removeAll { $0.id == id }
        dropExpired()
        persist()
    }

    /// Drops the deleted workspaces whose time is up from what is stored. Reading `bin` never
    /// shows them; this is for when the module starts.
    func purgeExpired() {
        guard binned.contains(where: isExpired) else { return }
        dropExpired()
        persist()
    }

    private func dropExpired() {
        binned.removeAll(where: isExpired)
    }

    private func isExpired(_ workspace: Workspace) -> Bool {
        guard let deletedAt = workspace.deletedAt else { return false }
        return now().timeIntervalSince(deletedAt) >= Double(Self.binDays) * Self.day
    }

    private static let day: TimeInterval = 24 * 60 * 60

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        workspaces.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    /// A locked workspace is a template: only a save the user asks for overwrites its checkpoint.
    func setLocked(_ locked: Bool, for id: UUID) {
        try? change(id) { $0.isLocked = locked }
    }

    /// A focused window that is not part of the workspace is dropped.
    func setOptions(_ options: WorkspaceOptions, for id: UUID) {
        try? change(id) { workspace in
            var options = options
            if let focus = options.focusedWindow, !workspace.windows.contains(where: { $0.id == focus }) {
                options.focusedWindow = nil
            }
            workspace.options = options
        }
    }

    /// A preview click saves the group's front tab and the expansion's final focus together.
    /// Only stored data changes; it never raises a live window or captures a new checkpoint.
    func selectPreviewWindow(_ entry: UUID, in id: UUID) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }),
              workspaces[index].windows.contains(where: { $0.id == entry }) else { return }
        var workspace = workspaces[index]
        for group in workspace.tabGroups.indices {
            let members = workspace.tabGroups[group].members
            if members.contains(entry) {
                workspace.tabGroups[group].active = entry
            } else if let previous = workspace.options.focusedWindow, members.contains(previous) {
                // Older checkpoints may have focused a tab other than the group's saved front.
                workspace.tabGroups[group].active = previous
            }
        }
        workspace.options.focusedWindow = entry
        guard workspace != workspaces[index] else { return }
        workspaces[index] = workspace
        persist()
    }

    /// Replaces what an entry opens. Any invalid target refuses the edit as a whole.
    func setContents(_ contents: [ReopenTarget], forWindow entry: UUID, in id: UUID) throws {
        let index = try self.index(of: entry, in: id)
        let bundleID = workspace(id: id)?.windows[index].bundleID
        if let error = contents.lazy.compactMap({ $0.validationError(bundleID: bundleID) }).first {
            throw WorkspaceLibraryError.invalidReopen(error)
        }
        try change(id) {
            $0.windows[index].contents = contents
            $0.windows[index].contentsAreCustom = true
        }
    }

    func setWindowing(_ windowing: Windowing, forWindow entry: UUID, in id: UUID) throws {
        let index = try self.index(of: entry, in: id)
        try change(id) { $0.windows[index].windowing = windowing }
    }

    /// Takes an entry out of the checkpoint; its window is not touched.
    func removeEntry(_ entry: UUID, from id: UUID) throws {
        _ = try index(of: entry, in: id)
        try change(id) { workspace in
            workspace.windows.removeAll { $0.id == entry }
            if workspace.options.focusedWindow == entry { workspace.options.focusedWindow = nil }
            workspace.tabGroups = workspace.tabGroups.compactMap { group in
                var group = group
                group.members.removeAll { $0 == entry }
                guard group.members.count >= 2, let first = group.members.first else { return nil }
                if group.active == entry { group.active = first }
                return group
            }
        }
    }

    /// Records the windows entries got when the checkpoint was expanded (workspaces design 5.1).
    /// Nothing else in the checkpoint changes. An entry that got none lets go of a window another
    /// entry now has.
    func recordWindows(_ refs: [UUID: WindowRef], in id: UUID) {
        guard !refs.isEmpty, let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        let taken = Set(refs.values)
        for item in workspaces[index].windows.indices {
            let entry = workspaces[index].windows[item]
            if let ref = refs[entry.id] {
                workspaces[index].windows[item].lastWindow = ref
            } else if let old = entry.lastWindow, taken.contains(old) {
                workspaces[index].windows[item].lastWindow = nil
            }
        }
        forget(taken, except: id)
        persist()
    }

    /// A window is remembered by one workspace only: the others let go of these.
    private func forget(_ refs: Set<WindowRef>, except keeper: UUID) {
        for index in workspaces.indices where workspaces[index].id != keeper {
            for item in workspaces[index].windows.indices {
                if let ref = workspaces[index].windows[item].lastWindow, refs.contains(ref) {
                    workspaces[index].windows[item].lastWindow = nil
                }
            }
        }
    }

    private func change(_ id: UUID, _ body: (inout Workspace) -> Void) throws {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else {
            throw WorkspaceLibraryError.missingWorkspace
        }
        body(&workspaces[index])
        persist()
    }

    private func index(of entry: UUID, in id: UUID) throws -> Int {
        guard let workspace = workspace(id: id) else { throw WorkspaceLibraryError.missingWorkspace }
        guard let index = workspace.windows.firstIndex(where: { $0.id == entry }) else {
            throw WorkspaceLibraryError.missingEntry
        }
        return index
    }

    private func defaultName() -> String {
        var number = workspaces.count + 1
        while workspaces.contains(where: { $0.name == L10n.text("workspaces.workspace.workspacelibrary", String(describing: (number))) }) { number += 1 }
        return L10n.text("workspaces.workspace.workspacelibrary", String(describing: (number)))
    }

    private func persist() {
        settings.save(WorkspaceSettings(workspaces: workspaces, bin: binned, autoSave: autoSave,
                                        autoSaveMinutes: autoSaveMinutes))
    }
}
