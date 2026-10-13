import Contracts
import CoreGraphics

/// Every tab group. Keeps three promises whatever happens: a window is in at most one group,
/// a group has at least two windows, and its active window is one of them.
struct TabBook: Equatable {
    private var groups: [TabGroupID: TabGroup] = [:]
    private var owners: [WindowID: TabGroupID] = [:]
    private var lastID = 0

    /// Every group, oldest first.
    var all: [TabGroup] { groups.values.sorted { $0.id.rawValue < $1.id.rawValue } }

    func group(_ id: TabGroupID) -> TabGroup? { groups[id] }
    func group(containing window: WindowID) -> TabGroup? { owners[window].flatMap { groups[$0] } }

    /// A new group of `members` in that order; nil unless there are two distinct windows, none
    /// in a group yet, and `active` is one of them.
    mutating func create(members: [WindowID], active: WindowID, area: CGRect, displayID: DisplayID?,
                         spaceID: SpaceID?) -> TabGroup? {
        var unique: [WindowID] = []
        for id in members where !unique.contains(id) { unique.append(id) }
        guard unique.count >= 2, unique.contains(active), unique.allSatisfy({ owners[$0] == nil }) else { return nil }
        lastID += 1
        let group = TabGroup(id: TabGroupID(rawValue: lastID), members: unique, active: active, area: area,
                             displayID: displayID, spaceID: spaceID)
        groups[group.id] = group
        for id in unique { owners[id] = group.id }
        return group
    }

    /// Adds a window that is in no group at `index` (appended when nil).
    @discardableResult
    mutating func add(_ window: WindowID, to id: TabGroupID, at index: Int? = nil, activate: Bool) -> TabGroup? {
        guard owners[window] == nil, var group = groups[id] else { return nil }
        let position = min(max(index ?? group.members.count, 0), group.members.count)
        group.members.insert(window, at: position)
        if activate { group.active = window }
        groups[id] = group
        owners[window] = id
        return group
    }

    enum Removal: Equatable {
        case notMember
        /// The group goes on without the window.
        case removed(TabGroup)
        /// Only `remaining` was left, so the group ended.
        case dissolved(TabGroup, remaining: WindowID)
    }

    /// A removed active tab passes to the tab on its right, or on its left when it was last.
    mutating func remove(_ window: WindowID) -> Removal {
        guard let id = owners.removeValue(forKey: window), var group = groups[id],
              let index = group.members.firstIndex(of: window) else { return .notMember }
        group.members.remove(at: index)
        guard group.members.count >= 2 else {
            groups[id] = nil
            for member in group.members { owners[member] = nil }
            return .dissolved(group, remaining: group.members[0])
        }
        if group.active == window { group.active = group.members[min(index, group.members.count - 1)] }
        groups[id] = group
        return .removed(group)
    }

    @discardableResult
    mutating func activate(_ window: WindowID) -> TabGroup? {
        guard let id = owners[window], var group = groups[id] else { return nil }
        group.active = window
        groups[id] = group
        return group
    }

    /// Moves a tab to `index` among the group's tabs as they are after the move.
    @discardableResult
    mutating func move(_ window: WindowID, to index: Int) -> TabGroup? {
        guard let id = owners[window], var group = groups[id], let from = group.members.firstIndex(of: window) else {
            return nil
        }
        group.members.remove(at: from)
        group.members.insert(window, at: min(max(index, 0), group.members.count))
        groups[id] = group
        return group
    }

    mutating func setArea(_ area: CGRect, displayID: DisplayID?, of id: TabGroupID) {
        groups[id]?.area = area
        groups[id]?.displayID = displayID
    }

    mutating func setSpace(_ space: SpaceID?, of id: TabGroupID) {
        groups[id]?.spaceID = space
    }

    /// Appends `other`'s tabs to `id`'s, keeping their order; `other` ends.
    @discardableResult
    mutating func absorb(_ other: TabGroupID, into id: TabGroupID) -> TabGroup? {
        guard other != id, let absorbed = groups[other], var group = groups[id] else { return nil }
        group.members += absorbed.members
        groups[other] = nil
        groups[id] = group
        for member in absorbed.members { owners[member] = id }
        return group
    }

    /// Ends the group; its windows belong to no group afterwards.
    @discardableResult
    mutating func dissolve(_ id: TabGroupID) -> TabGroup? {
        guard let group = groups.removeValue(forKey: id) else { return nil }
        for member in group.members { owners[member] = nil }
        return group
    }

    /// The tab `step` places from `window`'s, wrapping around.
    func neighbour(of window: WindowID, step: Int) -> WindowID? {
        guard let group = group(containing: window), let index = group.members.firstIndex(of: window) else { return nil }
        let count = group.members.count
        return group.members[((index + step) % count + count) % count]
    }
}
