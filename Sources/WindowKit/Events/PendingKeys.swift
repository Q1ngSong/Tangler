import Foundation

/// Keys of work already waiting in a queue. A window that moves sixty times a second needs
/// one read per turn of the queue, not sixty queued reads that would fall behind.
final class PendingKeys<Key: Hashable>: @unchecked Sendable {
    private let lock = NSLock()
    private var keys: Set<Key> = []

    /// False when the same work is already waiting.
    func admit(_ key: Key) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return keys.insert(key).inserted
    }

    /// Call right before doing the work, so changes after this point queue it again.
    func take(_ key: Key) {
        lock.lock()
        keys.remove(key)
        lock.unlock()
    }
}
