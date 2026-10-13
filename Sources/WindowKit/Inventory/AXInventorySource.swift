import ApplicationServices
import Contracts
import CoreGraphics
import Foundation

/// Reads windows from the window server and Accessibility. The private parts are optional:
/// without them windows are matched by geometry, carry no Spaces, and only windows
/// Accessibility lists (plus ones seen before) are found.
final class AXInventorySource: InventorySource, @unchecked Sendable {
    typealias Handle = AXHandle

    private static let attributes = [kAXPositionAttribute, kAXSizeAttribute, kAXTitleAttribute, kAXMinimizedAttribute,
                                     "AXFullScreen", kAXDocumentAttribute]

    private let stamps: ReadStamps
    private let identity: WindowIdentity?
    private let spaces: PrivateSpaces?
    private let remoteFinder: RemoteWindowFinder?

    init(stamps: ReadStamps, identity: WindowIdentity?, spaces: PrivateSpaces?, remoteFinder: RemoteWindowFinder?) {
        self.stamps = stamps
        self.identity = identity
        self.spaces = spaces
        self.remoteFinder = remoteFinder
    }

    func nextStamp() -> UInt64 { stamps.next() }

    func windowServerRecords() -> [WindowServerRecord]? {
        Self.records(CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID))
    }

    /// The window server's entry for one window; nil once it is gone.
    func record(of id: WindowID) -> WindowServerRecord? {
        Self.records(CGWindowListCopyWindowInfo(.optionIncludingWindow, id.rawValue))?.first { $0.id == id }
    }

    /// Windows on screen now, front to back.
    func onScreenRecords() -> [WindowServerRecord]? {
        Self.records(CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID))
    }

    func windows(of pid: Int32) -> [AXWindowSnapshot<AXHandle>]? {
        windows(of: pid, requiringCompleteRead: false)
    }

    /// Cleanup cannot interpret a partially readable application's list as proof of emptiness.
    func windows(of pid: Int32, requiringCompleteRead: Bool) -> [AXWindowSnapshot<AXHandle>]? {
        guard case .success(let value) = AXRead.value(AXRead.application(pid), kAXWindowsAttribute),
              let elements = value as? [AXUIElement] else { return nil }
        var snapshots: [AXWindowSnapshot<AXHandle>] = []
        for element in elements {
            if requiringCompleteRead {
                guard let role = AXRead.string(AXRead.attribute(element, kAXRoleAttribute)) else { return nil }
                // Finder includes the desktop's AXScrollArea in AXWindows. It has no window
                // number and is a desktop element, not an application window.
                guard role == kAXWindowRole else { continue }
            }
            if let snapshot = snapshot(of: element) { snapshots.append(snapshot) }
            else if requiringCompleteRead { return nil }
        }
        return snapshots
    }

    func reread(_ handle: AXHandle) -> AXWindowSnapshot<AXHandle>? {
        snapshot(of: handle.element)
    }

    func spaceIDs(of id: WindowID) -> [SpaceID]? {
        spaces?.spaceIDs(of: id)
    }

    func discoverWindows(of pid: Int32, missing: Set<WindowID>) -> [AXWindowSnapshot<AXHandle>] {
        remoteFinder?.windows(of: pid, missing: missing).compactMap(snapshot(of:)) ?? []
    }

    func forget(pid: Int32) {
        remoteFinder?.forget(pid: pid)
    }

    func focusedWindow(of pid: Int32) -> AXHandle? {
        AXRead.element(AXRead.attribute(AXRead.application(pid), kAXFocusedWindowAttribute)).map(AXHandle.init)
    }

    func snapshot(of element: AXUIElement) -> AXWindowSnapshot<AXHandle>? {
        AXUIElementSetMessagingTimeout(element, AXRead.timeout)
        let stamp = stamps.next()
        guard case .success(let values) = AXRead.attributes(element, Self.attributes) else { return nil }
        let frame = AXRead.point(values[0]).flatMap { origin in AXRead.size(values[1]).map { CGRect(origin: origin, size: $0) } }
        return AXWindowSnapshot(handle: AXHandle(element: element), exactID: identity?.windowID(of: element), frame: frame,
                                title: AXRead.string(values[2]) ?? "", isMinimized: AXRead.bool(values[3]) ?? false,
                                isFullscreen: AXRead.bool(values[4]) ?? false, documentURL: DocumentURL.accept(values[5]),
                                stamp: stamp)
    }

    private static func records(_ list: CFArray?) -> [WindowServerRecord]? {
        guard let entries = list as? [[String: Any]] else { return nil }
        return entries.enumerated().compactMap { WindowServerRecord($1, order: $0) }
    }
}
