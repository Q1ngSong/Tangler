import Contracts
import Foundation

/// What the matcher knows about an open window, or about a freshly captured one when a
/// checkpoint is saved.
struct WindowIdentity: Equatable, Sendable {
    var windowID: WindowID
    var pid: Int32
    var bundleID: String?
    var title: String
    /// Normalized like a reopen target, so the two compare directly.
    var documentURL: URL?

    init(_ window: WindowInfo) {
        windowID = window.id
        pid = window.pid
        bundleID = window.bundleID
        title = window.title
        documentURL = window.documentURL.flatMap { ReopenTarget.normalizedURL($0.absoluteString) }
    }

    /// Nil for an entry whose window was never seen.
    init?(_ window: SavedWindow) {
        guard let ref = window.lastWindow else { return nil }
        windowID = ref.windowID
        pid = ref.pid
        bundleID = window.bundleID
        title = window.title
        documentURL = window.documentIdentity
    }
}

extension SavedWindow {
    /// What identifies the entry besides its title: the first thing it opens.
    var documentIdentity: URL? { contents.first?.resourceURL }
}
