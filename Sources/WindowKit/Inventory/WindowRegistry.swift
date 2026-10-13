import Contracts
import Foundation

/// Every window WindowKit knows, and the only place that turns changes into WindowEvents.
/// Scans, notifications and frame readbacks run on different queues; read stamps decide
/// which of them saw each part of a window last (see `WindowFields`), so a slow scan cannot
/// undo a newer change, and a newer readback of the frame cannot hide an older title change.
final class WindowRegistry<Handle: Hashable>: @unchecked Sendable {
    struct Entry: Equatable {
        var info: WindowInfo
        var handle: Handle
        var stamps: FieldStamps

        init(info: WindowInfo, handle: Handle, stamps: FieldStamps) {
            self.info = info
            self.handle = handle
            self.stamps = stamps
        }

        init(info: WindowInfo, handle: Handle, stamp: UInt64) {
            self.init(info: info, handle: handle, stamps: FieldStamps(at: stamp))
        }

        /// The newest read of any part of the window.
        var stamp: UInt64 { stamps.newest }
    }

    private let lock = NSLock()
    private let emit: (WindowEvent) -> Void
    private let tombstoneLimit: Int
    private var entries: [WindowID: Entry] = [:]
    private var handles: [Handle: WindowID] = [:]
    private var order: [WindowID] = []
    /// When each removed window was confirmed gone; older reads of it are ignored.
    private var tombstones: [WindowID: UInt64] = [:]
    private var tombstoneOrder: [WindowID] = []
    private var focused: WindowID?
    private var primed = false

    init(tombstoneLimit: Int = 512, emit: @escaping (WindowEvent) -> Void) {
        self.tombstoneLimit = tombstoneLimit
        self.emit = emit
    }

    /// False until the first full scan, which fills the registry without broadcasting.
    var isPrimed: Bool { locked { primed } }
    var focusedID: WindowID? { locked { focused } }

    func entry(_ id: WindowID) -> Entry? { locked { entries[id] } }
    func id(for handle: Handle) -> WindowID? { locked { handles[handle] } }
    func entries(pid: Int32) -> [Entry] { locked { order.compactMap { entries[$0] }.filter { $0.info.pid == pid } } }
    func allEntries() -> [Entry] { locked { order.compactMap { entries[$0] } } }
    func infos() -> [WindowInfo] { allEntries().map(\.info) }

    func upsert(_ window: ScannedWindow<Handle>) {
        locked { broadcast(upsertLocked(window)) }
    }

    /// Changes the parts `fields` of a known window, e.g. its frame after a readback taken at
    /// `stamp`. Parts read later than `stamp` keep their newer value.
    func update(_ id: WindowID, fields: WindowFields, stamp: UInt64, change: (inout WindowInfo) -> Void) {
        locked {
            guard var entry = entries[id] else { return }
            let newer = entry.stamps.older(fields, than: stamp)
            guard !newer.isEmpty else { return }
            var changed = entry.info
            change(&changed)
            let old = entry.info
            entry.info.take(newer, from: changed)
            entry.stamps.set(newer, to: stamp)
            entries[id] = entry
            broadcast(WindowDiff.events(from: old, to: entry.info))
        }
    }

    /// Removes a window confirmed gone at `stamp`, unless something read it later.
    func remove(_ id: WindowID, stamp: UInt64) {
        locked {
            guard let entry = entries[id], entry.stamp < stamp else { return }
            broadcast(removeLocked(id, stamp: stamp))
        }
    }

    func removeAll(pid: Int32, stamp: UInt64) {
        locked {
            let ids = order.filter { entries[$0]?.info.pid == pid }
            broadcast(ids.flatMap { removeLocked($0, stamp: stamp) })
        }
    }

    func apply(_ scan: ScanResult<Handle>) {
        locked {
            var events = scan.windows.flatMap { upsertLocked($0) }
            let listed = Set(scan.windows.map(\.info.id))
            let unlisted = order.filter { !listed.contains($0) }
            for id in unlisted {
                guard let entry = entries[id], entry.stamp < scan.startStamp else { continue }
                let pid = entry.info.pid
                let applicationQuit = scan.runningPIDs.map { !$0.contains(pid) } ?? false
                // Only trust the window server's absence when the app answered too: a minimized
                // window can briefly drop out of the window server list. A closed window may
                // stay in that list, so the scan's verdict counts as well.
                let windowGone = scan.scannedPIDs.contains(pid)
                    && (scan.closedIDs.contains(id) || scan.liveWindowIDs.map { !$0.contains(id) } ?? false)
                if applicationQuit || windowGone { events += removeLocked(id, stamp: scan.startStamp) }
            }
            let front = scan.windows.map(\.info.id).filter { entries[$0] != nil }
            let frontSet = Set(front)
            order = front + order.filter { !frontSet.contains($0) && entries[$0] != nil }
            if scan.isFull && !primed {
                primed = true
                return
            }
            broadcast(events)
        }
    }

    func setFocused(_ id: WindowID) {
        locked {
            guard focused != id else { return }
            focused = id
            emit(.focused(id))
        }
    }

    // MARK: Locked helpers

    private func upsertLocked(_ window: ScannedWindow<Handle>) -> [WindowEvent] {
        let id = window.info.id
        if let removedAt = tombstones[id], window.stamp <= removedAt { return [] }
        var events: [WindowEvent] = []
        if let other = handles[window.handle], other != id {
            events += removeLocked(other, stamp: window.stamp)
        }
        guard var entry = entries[id] else {
            entries[id] = Entry(info: window.info, handle: window.handle,
                                stamps: FieldStamps(window.fields, at: window.stamp))
            handles[window.handle] = id
            tombstones[id] = nil
            order.insert(id, at: 0)
            return events + [.appeared(window.info)]
        }
        let newer = entry.stamps.older(window.fields, than: window.stamp)
        guard !newer.isEmpty else { return events }
        let old = entry.info
        entry.info.take(newer, from: window.info)
        entry.stamps.set(newer, to: window.stamp)
        // The handle goes with the details: both come from a full read of the element.
        if newer.contains(.details) && entry.handle != window.handle {
            handles[entry.handle] = nil
            entry.handle = window.handle
            handles[window.handle] = id
        }
        entries[id] = entry
        return events + WindowDiff.events(from: old, to: entry.info)
    }

    private func removeLocked(_ id: WindowID, stamp: UInt64) -> [WindowEvent] {
        guard let entry = entries.removeValue(forKey: id) else { return [] }
        if handles[entry.handle] == id { handles[entry.handle] = nil }
        order.removeAll { $0 == id }
        if focused == id { focused = nil }
        tombstones[id] = stamp
        tombstoneOrder.removeAll { $0 == id }
        tombstoneOrder.append(id)
        while tombstoneOrder.count > tombstoneLimit {
            tombstones[tombstoneOrder.removeFirst()] = nil
        }
        return [.disappeared(id)]
    }

    private func broadcast(_ events: [WindowEvent]) {
        guard primed else { return }
        // Sent while locked so concurrent changes reach subscribers in the order they were applied.
        events.forEach(emit)
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
