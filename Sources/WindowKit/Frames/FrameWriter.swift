import Contracts
import CoreGraphics
import Foundation

enum FrameWriteOutcome: Equatable {
    /// Written without reading back.
    case written
    /// Written and read back; `stamp` was taken just before the readback.
    case settled(CGRect, stamp: UInt64)
    case failed(WindowError)
}

/// One serial worker that holds at most one pending frame per window. A new frame replaces
/// the pending one, so a slow application receives only the newest target instead of a
/// backlog. Outcomes are delivered only for each window's newest request, so an interrupted
/// write can neither settle a newer one nor surface its stale error.
final class FrameWriter<Target>: @unchecked Sendable {
    struct Request {
        let id: WindowID
        let target: Target
        let frame: CGRect
        let verify: Bool
        let revision: UInt64
        /// True for the first write after a cancellation: anything cached about the window may be stale.
        let freshStart: Bool
    }

    private struct Pending {
        let request: Request
        let completion: (FrameWriteOutcome) -> Void
    }

    private let queue: DispatchQueue
    private let executor: OperationQueue?
    private let drains = DispatchGroup()
    private let apply: (Request) -> FrameWriteOutcome
    private let onIdle: () -> Void
    private let lock = NSLock()
    private var pending: [WindowID: Pending] = [:]
    private var pendingOrder: [WindowID] = []
    private var latestRevision: [WindowID: UInt64] = [:]
    private var written: Set<WindowID> = []
    private var revision: UInt64 = 0
    private var draining = false

    /// `onIdle` runs on the worker whenever it runs out of work. An optional shared executor
    /// limits how many app workers run at once, before they take a pending request.
    init(label: String = "app.local.tangler.window-frames", executor: OperationQueue? = nil,
         apply: @escaping (Request) -> FrameWriteOutcome,
         onIdle: @escaping () -> Void = {}) {
        queue = DispatchQueue(label: label, qos: .userInteractive)
        self.executor = executor
        self.apply = apply
        self.onIdle = onIdle
    }

    /// `completion` runs on the worker, only if this stays the window's newest request and it
    /// either verified or failed.
    func submit(_ id: WindowID, target: Target, frame: CGRect, verify: Bool,
                completion: @escaping (FrameWriteOutcome) -> Void) {
        lock.lock()
        revision &+= 1
        let request = Request(id: id, target: target, frame: frame, verify: verify, revision: revision, freshStart: false)
        if pending[id] == nil { pendingOrder.append(id) }
        pending[id] = Pending(request: request, completion: completion)
        latestRevision[id] = revision
        let start = !draining
        draining = true
        if start { drains.enter() }
        lock.unlock()
        if start {
            if let executor {
                executor.addOperation { [self] in queue.sync { drain() } }
            } else {
                queue.async { [self] in drain() }
            }
        }
    }

    /// Drops the window's pending frame and silences a write already in flight.
    func cancel(_ id: WindowID) {
        lock.lock()
        pending[id] = nil
        pendingOrder.removeAll { $0 == id }
        latestRevision[id] = nil
        written.remove(id)
        lock.unlock()
    }

    func cancelAll() {
        lock.lock()
        pending.removeAll()
        pendingOrder.removeAll()
        latestRevision.removeAll()
        written.removeAll()
        lock.unlock()
    }

    /// Runs `work` on the worker after every write submitted so far and waits for it.
    func performAndWait(_ work: () -> Void) {
        // A shared executor may not have started this worker yet. Cleanup must also wait
        // for those admitted drains, not merely for work already on the serial queue.
        drains.wait()
        queue.sync(execute: work)
    }

    private func drain() {
        defer { drains.leave() }
        while true {
            lock.lock()
            guard !pendingOrder.isEmpty else {
                draining = false
                lock.unlock()
                onIdle()
                return
            }
            let id = pendingOrder.removeFirst()
            guard let next = pending.removeValue(forKey: id) else {
                lock.unlock()
                continue
            }
            let fresh = written.insert(id).inserted
            lock.unlock()

            let request = Request(id: id, target: next.request.target, frame: next.request.frame,
                                  verify: next.request.verify, revision: next.request.revision, freshStart: fresh)
            let outcome = apply(request)
            lock.lock()
            let isCurrent = latestRevision[id] == request.revision
            lock.unlock()
            guard isCurrent else { continue }
            switch outcome {
            case .written: break
            case .settled, .failed: next.completion(outcome)
            }
        }
    }
}
