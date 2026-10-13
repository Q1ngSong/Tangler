import Foundation

/// A thread that runs its own CFRunLoop until stopped. The event tap's source lives here,
/// so a busy main thread never holds up keyboard and mouse input.
final class RunLoopThread: @unchecked Sendable {
    private let name: String
    private let lock = NSLock()
    private var thread: Thread?
    private var loop: CFRunLoop?
    private var stopping = false
    private let exited = DispatchSemaphore(value: 0)

    init(name: String) {
        self.name = name
    }

    var isRunning: Bool { lock.withLock { loop != nil } }

    /// Starts the thread with `source` in its run loop. Returns once the loop is ready.
    func start(with source: CFRunLoopSource) {
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            let loop = CFRunLoopGetCurrent()!
            CFRunLoopAddSource(loop, source, .commonModes)
            lock.withLock { self.loop = loop }
            ready.signal()
            while !lock.withLock({ stopping }) {
                // `.finished` means no source is left, e.g. the port died; nothing to wait for.
                if CFRunLoopRunInMode(.defaultMode, 60, false) == .finished { break }
            }
            CFRunLoopRemoveSource(loop, source, .commonModes)
            lock.withLock { self.loop = nil }
            exited.signal()
        }
        thread.name = name
        thread.qualityOfService = .userInteractive
        lock.withLock { self.thread = thread }
        thread.start()
        ready.wait()
    }

    /// Runs `block` on the thread.
    func perform(_ block: @escaping () -> Void) {
        guard let loop = lock.withLock({ loop }) else { return }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(loop)
    }

    /// Stops the loop and waits for the thread to exit, so nothing runs on it afterwards.
    func stop() {
        let target = lock.withLock { () -> (loop: CFRunLoop, thread: Thread?)? in
            guard let loop, !stopping else { return nil }
            stopping = true
            return (loop, thread)
        }
        guard let target else { return }
        // A stop request queued as a block cannot be lost, unlike CFRunLoopStop sent from
        // outside while the loop is between two runs.
        CFRunLoopPerformBlock(target.loop, CFRunLoopMode.defaultMode.rawValue) {
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        CFRunLoopWakeUp(target.loop)
        // Waiting on our own thread would never end; the loop exits after this call returns.
        if Thread.current != target.thread { exited.wait() }
    }
}
