import Foundation

/// Ties one live frame stream to its capture. Starting is asynchronous and the consumer may
/// leave first, so whichever comes second, the start or the leaving, stops the capture.
final class LiveSession: @unchecked Sendable {
    private let lock = NSLock()
    private var ended = false
    private var start: Task<Void, Never>?
    private var capture: (any LiveCapture)?

    /// Remembers the task starting the capture so `end()` can cancel it.
    func starting(_ task: Task<Void, Never>) {
        let alreadyEnded = lock.withLock {
            if !ended { start = task }
            return ended
        }
        if alreadyEnded { task.cancel() }
    }

    /// Keeps the started capture running, or stops it if the consumer already left.
    func attach(_ capture: any LiveCapture) async {
        let kept = lock.withLock {
            if !ended { self.capture = capture }
            return !ended
        }
        if !kept { await capture.stop() }
    }

    /// The consumer left or the stream finished.
    func end() {
        let (start, capture) = lock.withLock { () -> (Task<Void, Never>?, (any LiveCapture)?) in
            guard !ended else { return (nil, nil) }
            ended = true
            defer {
                self.start = nil
                self.capture = nil
            }
            return (self.start, self.capture)
        }
        start?.cancel()
        if let capture { Task { await capture.stop() } }
    }
}
