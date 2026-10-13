import Foundation

/// Fans one sequence of values out to any number of `AsyncStream` subscribers.
/// Each subscriber gets its own stream and is dropped when that stream terminates.
public final class Broadcaster<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]

    public init() {}

    public var subscriberCount: Int { locked { continuations.count } }

    /// A new stream that receives every value sent after this call.
    public func stream(bufferingNewest limit: Int = 256) -> AsyncStream<Element> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(limit)) { continuation in
            locked { continuations[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.locked { _ = self.continuations.removeValue(forKey: id) }
            }
        }
    }

    public func send(_ element: Element) {
        for continuation in locked({ Array(continuations.values) }) {
            continuation.yield(element)
        }
    }

    /// Ends every current stream.
    public func finish() {
        let all = locked { () -> [AsyncStream<Element>.Continuation] in
            defer { continuations.removeAll() }
            return Array(continuations.values)
        }
        for continuation in all { continuation.finish() }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
