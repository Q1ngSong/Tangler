import Foundation

/// Whether something with several start and stop steps is running. Starts and stops run one
/// at a time, so a stop never tears down what a start is still setting up; repeated starts
/// and stops do nothing.
final class Lifecycle: @unchecked Sendable {
    // Recursive, so a step that starts or stops again returns instead of deadlocking.
    private let lock = NSRecursiveLock()
    private var isStarted = false

    /// Runs `steps` unless already started; returns whether they ran.
    @discardableResult
    func start(_ steps: () -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isStarted else { return false }
        isStarted = true
        steps()
        return true
    }

    /// Runs `steps` if started; returns whether they ran.
    @discardableResult
    func stop(_ steps: () -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard isStarted else { return false }
        isStarted = false
        steps()
        return true
    }
}
