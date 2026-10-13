import Contracts
import CoreGraphics
import Foundation

/// One entry of a workspace: an application's window, where it goes and what it shows.
struct SavedWindow: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var bundleID: String?
    var appName: String
    /// Shown to the user, and compared with the windows a desktop already holds.
    var title: String
    var displayID: DisplayID
    /// The frame relative to the display's visible frame, which survives resolution changes.
    var unitFrame: UnitRect
    /// The absolute frame, kept as the fallback the placement service may use.
    var frame: CGRect
    /// The documents, folders and web pages to hand to the application for this window.
    var contents: [ReopenTarget] = []
    /// The user edited `contents`; saving a checkpoint then leaves them alone.
    var contentsAreCustom = false
    var windowing: Windowing = .automatic
    /// The window this entry last used; nil once it is known to be gone or was never seen.
    var lastWindow: WindowRef?
}

extension SavedWindow {
    /// Everything the entry opens, as one request; nil when it opens nothing or any target is invalid.
    var openRequest: OpenRequest? {
        guard let bundleID, !contents.isEmpty,
              contents.allSatisfy({ $0.validationError(bundleID: bundleID) == nil }) else { return nil }
        return OpenRequest(bundleID: bundleID, urls: contents.compactMap(\.resourceURL))
    }
}
