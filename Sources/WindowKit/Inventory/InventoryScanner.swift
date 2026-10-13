import Contracts
import CoreGraphics
import Foundation

/// Builds a `ScanResult` from window server and Accessibility reads, keeping the legacy
/// inventory rules: regular applications only, normal-layer windows larger than 40×24.
struct InventoryScanner<Source: InventorySource> {
    typealias Entry = WindowRegistry<Source.Handle>.Entry

    var source: Source
    var discoversOtherSpaces: Bool
    /// Reads applications in parallel, so one unresponsive app costs one timeout, not one per app.
    var concurrent: Bool

    func scan(apps: [AppSnapshot], isFull: Bool, known: [Entry], displays: [DisplayInfo]) -> ScanResult<Source.Handle> {
        let startStamp = source.nextStamp()
        let records = source.windowServerRecords()
        let context = Context(records: records, known: Dictionary(grouping: known, by: \.info.pid), displays: displays)
        var perApp = [AppScan?](repeating: nil, count: apps.count)
        if concurrent {
            let lock = NSLock()
            DispatchQueue.concurrentPerform(iterations: apps.count) { index in
                let scanned = scanApplication(apps[index], context: context)
                lock.lock()
                perApp[index] = scanned
                lock.unlock()
            }
        } else {
            for index in apps.indices { perApp[index] = scanApplication(apps[index], context: context) }
        }
        let found = perApp.compactMap { $0 }.flatMap(\.windows)
        let order = context.order
        let sorted = found.enumerated()
            .sorted { (order[$0.element.info.id] ?? Int.max, $0.offset) < (order[$1.element.info.id] ?? Int.max, $1.offset) }
            .map(\.element)
        return ScanResult(startStamp: startStamp, windows: sorted,
                          scannedPIDs: Set(zip(apps, perApp).filter { $0.1 != nil }.map(\.0.pid)),
                          runningPIDs: isFull ? Set(apps.map(\.pid)) : nil,
                          liveWindowIDs: records.map { Set($0.map(\.id)) },
                          closedIDs: Set(perApp.compactMap { $0 }.flatMap(\.closed)))
    }

    private struct AppScan {
        var windows: [ScannedWindow<Source.Handle>]
        var closed: [WindowID]
    }

    private struct Context {
        let records: [WindowServerRecord]?
        let recordsByID: [WindowID: WindowServerRecord]?
        let order: [WindowID: Int]
        let known: [Int32: [Entry]]
        let displays: [DisplayInfo]

        init(records: [WindowServerRecord]?, known: [Int32: [Entry]], displays: [DisplayInfo]) {
            self.records = records
            recordsByID = records.map { Dictionary($0.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }) }
            order = recordsByID?.mapValues(\.order) ?? [:]
            self.known = known
            self.displays = displays
        }
    }

    private func scanApplication(_ app: AppSnapshot, context: Context) -> AppScan? {
        guard let listed = source.windows(of: app.pid) else { return nil }
        let candidates = (context.records ?? []).filter { $0.pid == app.pid && $0.hasManageableShape }
        let known = context.known[app.pid] ?? []
        let previousIDs = Dictionary(known.map { ($0.handle, $0.info.id) }, uniquingKeysWith: { first, _ in first })
        var used = Set<WindowID>()
        var found: [ScannedWindow<Source.Handle>] = []
        var closed: [WindowID] = []

        for snapshot in listed {
            guard let frame = snapshot.frame, AXWindowSnapshot<Source.Handle>.hasManageableSize(frame),
                  let id = identify(snapshot, frame: frame, candidates: candidates, used: used,
                                    previousID: previousIDs[snapshot.handle], recordsByID: context.recordsByID),
                  used.insert(id).inserted else { continue }
            found.append(window(id, snapshot, frame: frame, app: app, context: context, spaceIDs: source.spaceIDs(of: id)))
        }
        // Known windows Accessibility stopped listing that the window server still has: kept
        // through their earlier handles while open elsewhere, reported closed otherwise.
        for entry in known where !used.contains(entry.info.id) && context.recordsByID?[entry.info.id] != nil {
            let id = entry.info.id
            let spaceIDs = source.spaceIDs(of: id)
            guard UnlistedWindows.isOpen(appIsHidden: app.isHidden, spaceIDs: spaceIDs) == true else {
                closed.append(id)
                continue
            }
            guard let snapshot = source.reread(entry.handle), let frame = snapshot.frame else { continue }
            used.insert(id)
            found.append(window(id, snapshot, frame: frame, app: app, context: context, spaceIDs: spaceIDs))
        }
        if discoversOtherSpaces {
            let missing = Set(candidates.map(\.id)).subtracting(used).subtracting(known.map(\.info.id)).filter {
                UnlistedWindows.isOpen(appIsHidden: app.isHidden, spaceIDs: source.spaceIDs(of: $0)) == true
            }
            if !missing.isEmpty {
                for snapshot in source.discoverWindows(of: app.pid, missing: missing) {
                    guard let id = snapshot.exactID, missing.contains(id), let frame = snapshot.frame,
                          used.insert(id).inserted else { continue }
                    found.append(window(id, snapshot, frame: frame, app: app, context: context,
                                        spaceIDs: source.spaceIDs(of: id)))
                }
            }
        }
        return AppScan(windows: found, closed: closed)
    }

    private func identify(_ snapshot: AXWindowSnapshot<Source.Handle>, frame: CGRect, candidates: [WindowServerRecord],
                          used: Set<WindowID>, previousID: WindowID?,
                          recordsByID: [WindowID: WindowServerRecord]?) -> WindowID? {
        if let exact = snapshot.exactID {
            guard let recordsByID else { return exact }
            if let record = recordsByID[exact] { return record.hasManageableShape ? exact : nil }
            return snapshot.isMinimized ? exact : nil
        }
        let available = candidates.filter { !used.contains($0.id) }
            .map { WindowMatcher.Candidate(id: $0.id, frame: $0.frame, title: $0.title) }
        // A minimized window can drop out of the window server list; keep its earlier identity.
        return WindowMatcher.match(frame: frame, title: snapshot.title, among: available, previousID: previousID)
            ?? (snapshot.isMinimized ? previousID : nil)
    }

    private func window(_ id: WindowID, _ snapshot: AXWindowSnapshot<Source.Handle>, frame: CGRect, app: AppSnapshot,
                        context: Context, spaceIDs: [SpaceID]?) -> ScannedWindow<Source.Handle> {
        let info = snapshot.info(id: id, frame: frame, app: app, displays: context.displays, spaceIDs: spaceIDs ?? [])
        return ScannedWindow(info: info, handle: snapshot.handle, stamp: snapshot.stamp)
    }
}
