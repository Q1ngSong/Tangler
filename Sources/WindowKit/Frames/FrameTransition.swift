import CoreGraphics

/// One window's path from one frame to another over time. Time-based rather than
/// frame-counted, so a slow application skips steps instead of slowing the animation down.
struct FrameTransition: Equatable {
    var from: CGRect
    var to: CGRect
    var start: Double
    var duration: Double

    func isFinished(at now: Double) -> Bool { progress(at: now) >= 1 }

    func frame(at now: Double) -> CGRect {
        let t = progress(at: now)
        if t >= 1 { return to }
        if t <= 0 { return from }
        let eased = 1 - pow(1 - t, 4)
        func step(_ a: CGFloat, _ b: CGFloat) -> CGFloat { (a + (b - a) * eased).rounded() }
        // Whole points avoid sub-point jitter in the intermediate frames.
        return CGRect(x: step(from.minX, to.minX), y: step(from.minY, to.minY),
                      width: step(from.width, to.width), height: step(from.height, to.height))
    }

    private func progress(at now: Double) -> Double {
        guard duration > 0, duration.isFinite else { return 1 }
        return min(1, max(0, (now - start) / duration))
    }
}
