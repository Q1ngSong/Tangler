/// How an open request ended.
enum OpenOutcome: Equatable, Sendable {
    /// macOS opened the request in the expected application. The window may still take a while.
    case opened
    case applicationNotFound
    case failed
    case timedOut
    case cancelled
}

/// Launches applications and opens documents, folders or web pages in them. Injected, so tests
/// never launch anything.
@MainActor
protocol ApplicationOpening: AnyObject {
    func isRunning(bundleID: String) -> Bool
    /// The process of a running application, which is how one without windows is reached.
    func pid(bundleID: String) -> Int32?
    func open(_ request: OpenRequest) async -> OpenOutcome
}
