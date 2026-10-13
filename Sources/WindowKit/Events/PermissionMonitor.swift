import Foundation

/// Polls a permission that has no change notification, such as Accessibility.
final class PermissionMonitor: @unchecked Sendable {
    private let interval: Double
    private let queue: DispatchQueue
    private let check: () -> Bool
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var last = false

    /// `check` must not prompt; it runs on `queue` every `interval` seconds.
    init(interval: Double = 1.5, queue: DispatchQueue, check: @escaping () -> Bool) {
        self.interval = interval
        self.queue = queue
        self.check = check
    }

    /// `onChange` runs on `queue` whenever the answer differs from the previous one. Does
    /// nothing while already started.
    func start(initial: Bool, onChange: @escaping (Bool) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        // Checked before the timer exists: libdispatch traps when a timer that never
        // started is released.
        guard timer == nil else { return }
        last = initial
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(Int(interval * 200)))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let current = self.check()
            self.lock.lock()
            let changed = current != self.last
            self.last = current
            self.lock.unlock()
            if changed { onChange(current) }
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        timer?.cancel()
        timer = nil
    }
}
