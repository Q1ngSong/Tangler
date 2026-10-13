import Foundation

/// What macOS reported for an open request.
struct OpenReply: Sendable {
    var bundleID: String?
    var failed: Bool
}

/// The macOS calls `ApplicationOpener` makes: NSWorkspace in the app, recorders in tests.
@MainActor
struct OpenEnvironment {
    typealias Completion = @MainActor @Sendable (OpenReply) -> Void

    var applicationURL: (String) -> URL?
    var isRunning: (String) -> Bool
    /// The process of a running application.
    var pid: (String) -> Int32?
    /// Starts opening; the completion may come late, twice or never.
    var open: (OpenRequest, URL, @escaping Completion) -> Void
}
