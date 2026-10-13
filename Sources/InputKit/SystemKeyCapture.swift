import Contracts
import Foundation

/// One key capture. It ends when `end()` is called, when the service stops, or when nobody
/// reads its keys any more: a finished stream can never deliver again, and swallowing keys
/// for it would leave the whole keyboard dead.
final class SystemKeyCapture: KeyCapture, @unchecked Sendable {
    let id: Int
    let keys: AsyncStream<KeyPress>

    private let continuation: AsyncStream<KeyPress>.Continuation
    private let onEnd: (Int) -> Void
    private let lock = NSLock()
    private var ended = false

    init(id: Int, onEnd: @escaping (Int) -> Void) {
        let (keys, continuation) = AsyncStream.makeStream(of: KeyPress.self)
        self.id = id
        self.keys = keys
        self.continuation = continuation
        self.onEnd = onEnd
        continuation.onTermination = { [weak self] _ in self?.end() }
    }

    func deliver(_ press: KeyPress) {
        continuation.yield(press)
    }

    func end() {
        let isFirst = lock.withLock { () -> Bool in
            defer { ended = true }
            return !ended
        }
        guard isFirst else { return }
        // Stop routing keys here before finishing, so no key is swallowed into a closed stream.
        onEnd(id)
        continuation.finish()
    }
}
