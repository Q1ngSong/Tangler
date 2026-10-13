import Foundation

/// A thread whose run loop delivers Accessibility observer callbacks. It keeps them off the
/// main thread and works whether or not a main run loop is spinning (under `swift test` it is not).
final class RunLoopThread: Thread, @unchecked Sendable {
    private let ready = DispatchSemaphore(value: 0)
    private var loop: CFRunLoop?

    /// Starts the thread and returns its run loop once it is running.
    func startLoop() -> CFRunLoop {
        start()
        ready.wait()
        return loop!
    }

    override func main() {
        let loop = CFRunLoopGetCurrent()!
        self.loop = loop
        // A run loop without sources returns at once; this one keeps it waiting for callbacks.
        var context = CFRunLoopSourceContext()
        CFRunLoopAddSource(loop, CFRunLoopSourceCreate(nil, 0, &context), .defaultMode)
        ready.signal()
        while !isCancelled {
            CFRunLoopRunInMode(.defaultMode, 60, false)
        }
    }

    /// Runs `block` on the thread, after any callback already in progress.
    func perform(_ block: @escaping () -> Void) {
        guard let loop else { return }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(loop)
    }

    func stopLoop() {
        cancel()
        if let loop { CFRunLoopStop(loop) }
    }
}
