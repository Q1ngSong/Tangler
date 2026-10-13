import Foundation

/// Answers lookups that may wait on a slow app, such as Dock hit tests polled while the
/// pointer moves, one at a time on `queue`. Requests made while a lookup runs wait for a
/// single follow-up lookup of the newest input and all get its answer: when input arrives
/// faster than the app answers, only the latest matters, and blocked threads cannot pile up.
final class LatestLookup<Input, Output>: @unchecked Sendable {
    private struct Pending {
        var input: Input
        var waiters: [(Output) -> Void]
    }

    private let queue: DispatchQueue
    private let lookup: (Input) -> Output
    private let lock = NSLock()
    private var running = false
    private var pending: Pending?

    init(queue: DispatchQueue, lookup: @escaping (Input) -> Output) {
        self.queue = queue
        self.lookup = lookup
    }

    func value(for input: Input) async -> Output {
        await withCheckedContinuation { continuation in
            request(input) { continuation.resume(returning: $0) }
        }
    }

    /// `completion` runs on `queue`.
    func request(_ input: Input, completion: @escaping (Output) -> Void) {
        lock.lock()
        guard !running else {
            pending = Pending(input: input, waiters: (pending?.waiters ?? []) + [completion])
            lock.unlock()
            return
        }
        running = true
        lock.unlock()
        queue.async { [self] in run(Pending(input: input, waiters: [completion])) }
    }

    private func run(_ first: Pending) {
        var next = first
        while true {
            let output = lookup(next.input)
            next.waiters.forEach { $0(output) }
            lock.lock()
            guard let waiting = pending else {
                running = false
                lock.unlock()
                return
            }
            pending = nil
            lock.unlock()
            next = waiting
        }
    }
}
