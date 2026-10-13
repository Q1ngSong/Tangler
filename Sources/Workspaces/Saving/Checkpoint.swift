import Contracts
import Foundation

/// Overwriting a checkpoint with a fresh capture (workspaces design 6.2). Captured windows
/// are paired with the old entries; a paired entry keeps its identity, its windowing and
/// contents the user edited. Old entries without a window are dropped, new windows are added.
/// The focus is the captured one, else the entry chosen before. The tab groups are the captured
/// ones, and with `.keepUnseen` also the saved ones the capture shows nothing of.
enum Checkpoint {
    /// What a save makes of the saved tab groups the capture shows nothing of.
    enum Groups {
        /// The desktop is the truth: a group the user dissolved leaves the checkpoint.
        case captured
        /// The tab group service forgets its groups when Tangler restarts and may be off. Until
        /// the saved groups are back on the desktop, a capture without a group says nothing
        /// about them: they stay while their members do.
        case keepUnseen
    }

    /// The old entries in `keeping` that have no window stay as they were, after the captured
    /// ones: a save nobody asked for keeps what the last expansion did not deliver.
    static func overwrite(_ original: Workspace, with captured: WindowCapture.Result, at time: Date,
                          keeping: Set<UUID> = [], groups saving: Groups = .keepUnseen) -> Workspace {
        let pairs = WindowMatcher.match(original.windows, with: captured.windows.compactMap(WindowIdentity.init),
                                        contentsMustAgree: false)
        var windows = captured.windows
        var renamed: [UUID: UUID] = [:]
        for (oldIndex, windowID) in pairs {
            guard let index = windows.firstIndex(where: { $0.lastWindow?.windowID == windowID }) else { continue }
            let old = original.windows[oldIndex]
            renamed[windows[index].id] = old.id
            windows[index].id = old.id
            windows[index].windowing = old.windowing
            if old.contentsAreCustom {
                windows[index].contents = old.contents
                windows[index].contentsAreCustom = true
            }
        }
        func id(_ captured: UUID) -> UUID { renamed[captured] ?? captured }
        let groups = captured.tabGroups.map {
            SavedTabGroup(members: $0.members.map(id), active: id($0.active), unitArea: $0.unitArea)
        }
        let seen = Set(windows.map(\.id))
        let taken = Set(windows.compactMap(\.lastWindow))
        let kept = original.windows.filter { keeping.contains($0.id) && !seen.contains($0.id) }
        windows += kept.map { entry in
            var entry = entry
            if let ref = entry.lastWindow, taken.contains(ref) { entry.lastWindow = nil }
            return entry
        }
        var workspace = original
        workspace.windows = windows
        workspace.tabGroups = keepingGroups(of: original, for: Set(kept.map(\.id)), in: groups, entries: windows,
                                            saving: saving)
        workspace.savedAt = time
        workspace.screenAspect = captured.screenAspect
        // A capture without a focus, as from the settings page where Tangler's own window has
        // it, keeps the entry the user chose while that entry is still there.
        let chosen = original.options.focusedWindow.flatMap { old in windows.contains { $0.id == old } ? old : nil }
        workspace.options.focusedWindow = captured.focused.map(id) ?? chosen
        return workspace
    }

    /// The captured groups, then the saved ones they leave standing. A captured group replaces
    /// every saved group it shares a member with, and a kept entry of such a group joins it,
    /// last. Any other saved group stays with the members that are still entries, while there
    /// are two: a member whose window is gone leaves it. With `.captured` only a saved group
    /// with a kept entry stays like that: its window never came, so nobody dissolved the group.
    private static func keepingGroups(of original: Workspace, for kept: Set<UUID>, in captured: [SavedTabGroup],
                                      entries: [SavedWindow], saving: Groups) -> [SavedTabGroup] {
        var groups = captured
        let present = Set(entries.map(\.id))
        for old in original.tabGroups where saving == .keepUnseen || old.members.contains(where: kept.contains) {
            if let index = captured.firstIndex(where: { !Set($0.members).isDisjoint(with: old.members) }) {
                groups[index].members += old.members.filter(kept.contains)
                continue
            }
            let members = old.members.filter(present.contains)
            guard members.count >= 2 else { continue }
            groups.append(SavedTabGroup(members: members, active: members.contains(old.active) ? old.active : members[0],
                                        unitArea: old.unitArea))
        }
        return groups
    }
}
