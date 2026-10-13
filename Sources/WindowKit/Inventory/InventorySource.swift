import Contracts
import CoreGraphics
import Foundation

struct AppSnapshot: Equatable, Sendable {
    var pid: Int32
    var bundleID: String?
    var name: String
    var isHidden = false
}

/// One Accessibility read of a window.
struct AXWindowSnapshot<Handle> {
    var handle: Handle
    /// From the private lookup; nil when it is unavailable or failed.
    var exactID: WindowID?
    var frame: CGRect?
    var title: String
    var isMinimized: Bool
    var isFullscreen: Bool
    var documentURL: URL?
    /// Taken just before the read.
    var stamp: UInt64
}

/// The system reads a scan needs. Implemented with the window server and Accessibility in
/// production and with scripted answers in tests. Must be safe to call from several threads.
protocol InventorySource {
    associatedtype Handle: Hashable

    func nextStamp() -> UInt64
    /// Every window, front to back; nil when the list could not be read.
    func windowServerRecords() -> [WindowServerRecord]?
    /// The windows Accessibility lists for an application; nil when it did not answer.
    func windows(of pid: Int32) -> [AXWindowSnapshot<Handle>]?
    /// Reads a window again through a handle from an earlier scan; nil once it is gone.
    func reread(_ handle: Handle) -> AXWindowSnapshot<Handle>?
    /// The Spaces showing a window; empty when it is on none, e.g. closed but kept by its app;
    /// nil when Spaces cannot be read.
    func spaceIDs(of id: WindowID) -> [SpaceID]?
    /// Looks for windows Accessibility does not list, such as windows on other Spaces.
    func discoverWindows(of pid: Int32, missing: Set<WindowID>) -> [AXWindowSnapshot<Handle>]
}
