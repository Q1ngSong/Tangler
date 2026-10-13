import CoreKit
import Contracts
import CoreGraphics
import Foundation

/// Everything between a frame request and its readback: the animator, confined to its own
/// queue, and a coalescing writer per application. A slow app cannot block another app's
/// windows; windows of the same app share a worker and its Accessibility state. Up to four
/// app workers run at once to bound the burst of AX calls and app redraws.
final class FramePipeline<Backend: FrameBackend>: @unchecked Sendable {
    typealias Target = FrameTarget<Backend.Element>

    private final class WeakAnimator: @unchecked Sendable {
        weak var animator: WindowAnimator<Target>?
    }

    /// Accessed only on animationQueue. Each worker owns its applier's caches and the
    /// application's AXEnhancedUserInterface flag, so those never cross worker threads.
    private final class ApplicationWriters {
        typealias Worker = (applier: FrameApplier<Backend>, writer: FrameWriter<Target>)
        private let backend: Backend
        private let executor: OperationQueue
        private var byPID: [Int32: Worker] = [:]

        init(backend: Backend) {
            self.backend = backend
            executor = OperationQueue()
            executor.name = "app.local.tangler.window-frame-workers"
            executor.qualityOfService = .userInteractive
            executor.maxConcurrentOperationCount = 4
        }

        func writer(for pid: Int32) -> FrameWriter<Target> {
            if let existing = byPID[pid] { return existing.writer }
            let applier = FrameApplier(backend: backend)
            let writer = FrameWriter<Target>(label: "app.local.tangler.window-frames.\(pid)", executor: executor,
                                             apply: { applier.apply($0) })
            byPID[pid] = (applier, writer)
            return writer
        }

        func cancel(_ id: WindowID) {
            for worker in byPID.values { worker.writer.cancel(id) }
        }

        func takeAll() -> [Worker] {
            let workers = Array(byPID.values)
            byPID.removeAll()
            return workers
        }
    }

    private let backend: Backend
    private let animationQueue: DispatchQueue
    /// Reads that may wait on a slow app; concurrent so they never queue behind each other.
    private let readQueue = DispatchQueue(label: "app.local.tangler.window-frame-reads", qos: .userInitiated,
                                          attributes: .concurrent)
    private let writers: ApplicationWriters
    /// Used only on `animationQueue`.
    private let animator: WindowAnimator<Target>

    init(backend: Backend, clockInterval: Double = 1.0 / 120) {
        let writers = ApplicationWriters(backend: backend)
        let animationQueue = DispatchQueue(label: "app.local.tangler.window-animation", qos: .userInteractive)
        // The animator owns the clock, so the clock reaches back to it only weakly.
        let animatorBox = WeakAnimator()
        let clock = DispatchAnimationClock(queue: animationQueue, interval: clockInterval) {
            animatorBox.animator?.tick(now: ProcessInfo.processInfo.systemUptime)
        }
        let animator = WindowAnimator<Target>(
            submit: { id, target, frame, verify, completion in
                writers.writer(for: target.pid).submit(id, target: target, frame: frame, verify: verify) { outcome in
                    animationQueue.async { completion(outcome) }
                }
            },
            resetWrites: { writers.cancel($0) },
            clock: clock)
        animatorBox.animator = animator
        self.backend = backend
        self.animationQueue = animationQueue
        self.writers = writers
        self.animator = animator
    }

    /// Moves a window to `frame` over `duration` seconds; answers with the readback, or with
    /// the newest target's readback when a later move interrupts this one. The move starts
    /// from where the window really is, since the user may have moved it after the inventory
    /// last heard; `fallback` stands in when it cannot be read.
    func move(_ id: WindowID, target: Target, to frame: CGRect, duration: Double,
              fallback: CGRect) async -> FrameWriteOutcome {
        let backend = self.backend
        let start = await withCheckedContinuation { continuation in
            readQueue.async { continuation.resume(returning: (try? backend.frame(of: target.element).get()) ?? fallback) }
        }
        let animator = self.animator
        return await withCheckedContinuation { continuation in
            animationQueue.async {
                animator.move(id, target: target, from: start, to: frame, duration: duration,
                              now: ProcessInfo.processInfo.systemUptime) { continuation.resume(returning: $0) }
            }
        }
    }

    /// Ends running animations, drops queued writes and gives apps back their
    /// `AXEnhancedUserInterface` flag, all before returning, so it also holds when the app
    /// quits right after. The animator stops first: a frame it still had queued could
    /// otherwise turn the flag off again after it was restored. Must not be called from the
    /// pipeline's own queues.
    func stop() {
        let workers = animationQueue.sync {
            animator.stop(error: .rejected(L10n.text("windowkit.the.window.service.has.stopped")))
            return writers.takeAll()
        }
        for worker in workers { worker.writer.cancelAll() }
        for worker in workers {
            worker.writer.performAndWait { worker.applier.restoreEnhancedUserInterface() }
        }
    }
}
