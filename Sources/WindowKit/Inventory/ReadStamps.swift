import Foundation

/// Orders reads made on different queues: a larger stamp was taken later. The registry uses
/// it to keep the newest knowledge of each window, whichever queue delivered it.
final class ReadStamps: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0

    func next() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}
