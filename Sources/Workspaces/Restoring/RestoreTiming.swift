/// How long restoring and expanding wait for windows to appear. Injected, so tests never really wait.
struct RestoreTiming: Sendable {
    var pollInterval: Duration = .milliseconds(250)
    /// Polls after each document opens before the next request, so an application that brings
    /// back several documents at once is not asked for them again. When expanding, the polls a
    /// launched application gets to bring back the entry's own window once it shows any.
    var pollsAfterOpen = 8
    /// Polls at the end for the windows of opened documents and launched applications. When
    /// expanding, the polls for a launched application's first window.
    var pollsAtEnd = 40
    /// Polls for the window of contents handed to a running application: 3 seconds.
    var pollsForNewWindow = 12
    var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
}
