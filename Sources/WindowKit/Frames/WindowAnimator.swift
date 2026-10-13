import Contracts
import CoreGraphics

/// Drives `WindowAnimator.tick(now:)` while any window is animating.
protocol AnimationClock: AnyObject {
    func start()
    func stop()
}

/// Coordinates every frame request. Animations follow a time-based clock and can be
/// interrupted: a new target continues from the frame the window is at, and every caller
/// still waiting is answered with the readback of the newest target once it settles.
/// Not thread-safe: the owner confines it to one serial queue, hence the unchecked Sendable.
final class WindowAnimator<Target>: @unchecked Sendable {
    typealias Completion = (FrameWriteOutcome) -> Void
    /// Writes a frame; `verify` asks for a readback. The writer answers only for the
    /// window's newest request, and only with a readback or a failure.
    typealias Submit = (_ id: WindowID, _ target: Target, _ frame: CGRect, _ verify: Bool,
                        _ completion: @escaping Completion) -> Void

    private struct Job {
        var target: Target
        var destination: CGRect
        var transition: FrameTransition?
        var lastSubmitted: CGRect?
        var completions: [Completion]
    }

    private struct Settlement {
        var target: CGRect
        var actual: CGRect
        var stamp: UInt64
    }

    private let submit: Submit
    private let resetWrites: (WindowID) -> Void
    private let clock: AnimationClock
    private var jobs: [WindowID: Job] = [:]
    private var settled: [WindowID: Settlement] = [:]

    /// `resetWrites` cancels the window's pending writes and makes the next one re-read the
    /// window, which matters when someone else moved it since the last interaction.
    init(submit: @escaping Submit, resetWrites: @escaping (WindowID) -> Void, clock: AnimationClock) {
        self.submit = submit
        self.resetWrites = resetWrites
        self.clock = clock
    }

    /// `frame` stays as given; the applier rounds it to whole points when it writes.
    func move(_ id: WindowID, target: Target, from current: CGRect, to frame: CGRect, duration: Double, now: Double,
              completion: @escaping Completion) {
        let destination = frame
        if var job = jobs[id] {
            job.completions.append(completion)
            job.target = target
            // Repeating the running target must not restart its easing curve.
            guard !Self.isWithinAPoint(job.destination, destination) else {
                jobs[id] = job
                return
            }
            let start = job.transition?.frame(at: now) ?? job.lastSubmitted ?? current
            job.destination = destination
            begin(id, job, from: start, duration: duration, now: now)
            return
        }
        // The app already constrained this target (e.g. a minimum size) and nothing moved
        // since: report that result again instead of fighting the app over it.
        if let settlement = settled[id], Self.isWithinAPoint(settlement.target, destination),
           Self.isWithinAPoint(current, settlement.actual) {
            completion(.settled(settlement.actual, stamp: settlement.stamp))
            return
        }
        settled[id] = nil
        resetWrites(id)
        begin(id, Job(target: target, destination: destination, transition: nil, lastSubmitted: nil,
                      completions: [completion]), from: current, duration: duration, now: now)
    }

    func tick(now: Double) {
        for (id, job) in jobs {
            guard let transition = job.transition else { continue }
            if transition.isFinished(at: now) {
                verify(id)
                continue
            }
            let frame = transition.frame(at: now)
            guard frame != job.lastSubmitted else { continue }
            var updated = job
            updated.lastSubmitted = frame
            jobs[id] = updated
            submit(id, job.target, frame, false) { [weak self] outcome in self?.writeFailed(id, outcome: outcome) }
        }
        stopClockIfIdle()
    }

    func cancel(_ id: WindowID, error: WindowError) {
        settled[id] = nil
        guard let job = jobs.removeValue(forKey: id) else { return }
        resetWrites(id)
        job.completions.forEach { $0(.failed(error)) }
        stopClockIfIdle()
    }

    func stop(error: WindowError) {
        let interrupted = jobs
        jobs.removeAll()
        settled.removeAll()
        clock.stop()
        for (id, job) in interrupted {
            resetWrites(id)
            job.completions.forEach { $0(.failed(error)) }
        }
    }

    private func begin(_ id: WindowID, _ job: Job, from start: CGRect, duration: Double, now: Double) {
        var job = job
        if duration > 0, duration.isFinite, !Self.isWithinAPoint(start, job.destination) {
            job.transition = FrameTransition(from: start, to: job.destination, start: now, duration: duration)
            jobs[id] = job
            clock.start()
        } else {
            jobs[id] = job
            verify(id)
            stopClockIfIdle()
        }
    }

    private func verify(_ id: WindowID) {
        guard var job = jobs[id] else { return }
        let destination = job.destination
        job.transition = nil
        job.lastSubmitted = destination
        jobs[id] = job
        submit(id, job.target, destination, true) { [weak self] outcome in
            self?.finish(id, destination: destination, outcome: outcome)
        }
    }

    private func finish(_ id: WindowID, destination: CGRect, outcome: FrameWriteOutcome) {
        // A newer target may have arrived after this readback was requested.
        guard let job = jobs[id], job.destination == destination, job.transition == nil else { return }
        jobs[id] = nil
        if case .settled(let actual, let stamp) = outcome {
            settled[id] = Settlement(target: destination, actual: actual, stamp: stamp)
        }
        job.completions.forEach { $0(outcome) }
        stopClockIfIdle()
    }

    private func writeFailed(_ id: WindowID, outcome: FrameWriteOutcome) {
        guard case .failed = outcome, let job = jobs.removeValue(forKey: id) else { return }
        job.completions.forEach { $0(outcome) }
        stopClockIfIdle()
    }

    private func stopClockIfIdle() {
        if !jobs.values.contains(where: { $0.transition != nil }) { clock.stop() }
    }

    /// Windows are written in whole points, so frames less than a point apart on every edge
    /// count as the same.
    private static func isWithinAPoint(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 1 && abs(a.minY - b.minY) < 1 && abs(a.width - b.width) < 1 && abs(a.height - b.height) < 1
    }
}
