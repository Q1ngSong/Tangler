import Foundation

/// Ticks on the animator's queue while any window animates. Writes are coalesced per
/// window, so ticking faster than an app can follow only drops steps, never queues them.
/// `start` and `stop` must be called on `queue`.
final class DispatchAnimationClock: AnimationClock {
    private let queue: DispatchQueue
    private let interval: Double
    private let tick: () -> Void
    private var timer: DispatchSourceTimer?

    init(queue: DispatchQueue, interval: Double = 1.0 / 120, tick: @escaping () -> Void) {
        self.queue = queue
        self.interval = interval
        self.tick = tick
    }

    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(1))
        timer.setEventHandler { [tick] in tick() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }
}
