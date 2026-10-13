import AppKit
import Contracts
import CoreGraphics

extension SystemWindowService {
    public func windows() async -> [WindowInfo] {
        guard await prepare(prime: false) else { return [] }
        await scans.scan(.all)
        return registry.infos()
    }

    public func window(_ id: WindowID) async -> WindowInfo? {
        guard await prepare(), let entry = await entry(for: id) else { return nil }
        // Read it again, so the answer includes changes whose notifications are still on the way,
        // and the Spaces it is on, which no notification reports.
        let handler = self.handler!
        await run(on: eventQueue) { handler.refresh(entry.handle, pid: entry.info.pid) }
        return registry.entry(id)?.info
    }

    public func focusedWindowID() async -> WindowID? {
        guard await prepare() else { return nil }
        let handler = self.handler!
        if let id = await run(on: eventQueue, { handler.focusedWindowID() }) { return id }
        // A window the inventory has not met yet: read its application, then ask again.
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier, pid != ownPID else { return nil }
        await scans.scan(.applications([pid]))
        return await run(on: eventQueue) { handler.focusedWindowID() }
    }

    public func windowID(at point: CGPoint) async -> WindowID? {
        guard await prepare() else { return nil }
        let registry = self.registry
        let ownPID = self.ownPID
        guard let records = source.onScreenRecords() else {
            return WindowHitTest.windowID(at: point, in: registry.infos(), ownPID: ownPID)
        }
        return await WindowHitTest.windowID(at: point, in: records, ownPID: ownPID, knowledge: { id in
            guard let entry = registry.entry(id) else { return .unknown }
            return entry.info.isMinimized ? .minimized : .managed
        }, learn: { [weak self] record in
            guard let self, Self.application(record.pid, ownPID: ownPID) != nil else { return false }
            return await self.entry(for: record.id).map { !$0.info.isMinimized } ?? false
        })
    }

    public func displays() async -> [DisplayInfo] {
        start()
        return await refreshDisplays()
    }

    public func isSpaceEmpty(_ space: SpaceID) async -> Bool? {
        guard capabilities.contains(.spaceList), await prepare(prime: false) else { return nil }
        guard let privateSpaces,
              await spaces().contains(where: { $0.id == space && !$0.isFullscreen }) else { return nil }
        let (apps, ownWindows) = await MainActor.run {
            let own = NSApp?.windows.filter { $0.styleMask.contains(.titled) && ($0.isVisible || $0.isMiniaturized) }
                .compactMap { window -> WindowInfo? in
                    guard window.windowNumber > 0 else { return nil }
                    return WindowInfo(id: WindowID(rawValue: UInt32(window.windowNumber)), pid: self.ownPID,
                                      appName: "Tangler", title: "", frame: .zero)
                } ?? []
            return (Self.manageableApplications(excluding: self.ownPID), own)
        }
        let source = self.source
        let known = registry.allEntries()
        let displays = displayCache.value
        // A normal inventory may omit an unresponsive application or an unidentified minimized
        // window. Deletion needs a complete read, not an empty best-effort `windows()` result.
        return await run(on: actionQueue) {
            var windows = ownWindows
            for app in apps {
                guard let snapshots = source.windows(of: app.pid, requiringCompleteRead: true) else { return nil }
                for snapshot in snapshots {
                    guard let frame = snapshot.frame else { return nil }
                    guard AXWindowSnapshot<AXHandle>.hasManageableSize(frame) else { continue }
                    guard let id = snapshot.exactID ?? known.first(where: { $0.handle == snapshot.handle })?.info.id else {
                        return nil
                    }
                    windows.append(snapshot.info(id: id, frame: frame, app: app, displays: displays,
                                                 spaceIDs: source.spaceIDs(of: id) ?? []))
                }
            }
            guard let records = source.windowServerRecords() else { return nil }
            return SpaceOccupancy.isEmpty(on: space, records: records, windows: windows,
                                          hiddenPIDs: Set(apps.filter(\.isHidden).map(\.pid)), ownPID: self.ownPID) {
                privateSpaces.spaceIDs(of: $0)
            }
        }
    }

    public func spaces() async -> [SpaceInfo] {
        guard let privateSpaces, let raw = privateSpaces.displaySpaces() else { return [] }
        let main = await currentDisplays().first(where: \.isMain)?.id
        return SpaceParser.spaces(from: raw, mainDisplayID: main)
    }

    public func dockFrame() async -> CGRect? {
        start()
        guard isAuthorized else { return nil }
        return await run(on: dockFrameQueue) { DockReader.dockFrame() }
    }

    public func dockItem(at point: CGPoint) async -> DockItem? {
        start()
        guard isAuthorized else { return nil }
        let displays = await currentDisplays()
        return await dockLookup.value(for: (point, displays))
    }
}
