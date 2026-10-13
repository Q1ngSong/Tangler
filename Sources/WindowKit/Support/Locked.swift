import Foundation

/// A value guarded by a lock, for state shared between queues.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) {
        stored = value
    }

    var value: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
        set {
            lock.lock()
            stored = newValue
            lock.unlock()
        }
    }

    @discardableResult
    func update<T>(_ change: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return change(&stored)
    }
}
