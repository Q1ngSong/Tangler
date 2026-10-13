import Contracts
import Foundation

/// Fans input events out to subscribers, each with its own filter.
final class EventHub: @unchecked Sendable {
    private struct Subscriber {
        let filter: InputEventFilter
        let continuation: AsyncStream<InputEvent>.Continuation
    }

    private let lock = NSLock()
    private var subscribers: [UUID: Subscriber] = [:]
    private var mouseMovedSubscribers = 0

    /// Whether anyone asked for `.mouseMoved`; the tap does not even read moves otherwise.
    var wantsMouseMoved: Bool { lock.withLock { mouseMovedSubscribers > 0 } }
    var subscriberCount: Int { lock.withLock { subscribers.count } }

    /// A new stream with every later event that `filter` admits.
    func stream(_ filter: InputEventFilter) -> AsyncStream<InputEvent> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(256)) { continuation in
            lock.withLock {
                subscribers[id] = Subscriber(filter: filter, continuation: continuation)
                if filter.contains(.mouseMoved) { mouseMovedSubscribers += 1 }
            }
            continuation.onTermination = { [weak self] _ in self?.remove(id) }
        }
    }

    func send(_ event: InputEvent) {
        let targets = lock.withLock { subscribers.values.filter { $0.filter.admits(event) }.map(\.continuation) }
        for continuation in targets { continuation.yield(event) }
    }

    /// Ends every current stream.
    func finish() {
        let all = lock.withLock { () -> [AsyncStream<InputEvent>.Continuation] in
            defer {
                subscribers.removeAll()
                mouseMovedSubscribers = 0
            }
            return subscribers.values.map(\.continuation)
        }
        for continuation in all { continuation.finish() }
    }

    private func remove(_ id: UUID) {
        lock.withLock {
            guard let removed = subscribers.removeValue(forKey: id) else { return }
            if removed.filter.contains(.mouseMoved) { mouseMovedSubscribers -= 1 }
        }
    }
}
