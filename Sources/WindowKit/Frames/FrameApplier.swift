import CoreKit
import Contracts
import CoreGraphics

/// The Accessibility calls a frame write needs, injectable so the write logic can be tested.
protocol FrameBackend {
    associatedtype Element

    func settable(_ element: Element) -> (movable: Bool, resizable: Bool)
    func frame(of element: Element) -> Result<CGRect, AXFailure>
    func setSize(_ size: CGSize, of element: Element) -> AXFailure?
    func setPosition(_ origin: CGPoint, of element: Element) -> AXFailure?
    /// The application's `AXEnhancedUserInterface` flag; nil when it cannot be read.
    func enhancedUserInterface(pid: Int32) -> Bool?
    func setEnhancedUserInterface(_ enabled: Bool, pid: Int32)
    func nextStamp() -> UInt64
}

struct FrameTarget<Element> {
    var element: Element
    var pid: Int32
    var appName: String
}

/// Applies one frame request. Runs only on the frame writer's worker, which owns its caches.
final class FrameApplier<Backend: FrameBackend> {
    typealias Target = FrameTarget<Backend.Element>

    private struct CachedWindow {
        var movable: Bool
        var resizable: Bool
        var lastWritten: CGRect?
    }

    private let backend: Backend
    private let cacheLimit = 128
    private var cache: [WindowID: CachedWindow] = [:]
    private var checkedEnhanced: Set<Int32> = []
    private var suspendedEnhanced: Set<Int32> = []

    init(backend: Backend) {
        self.backend = backend
    }

    func apply(_ request: FrameWriter<Target>.Request) -> FrameWriteOutcome {
        let target = request.target
        if request.freshStart { cache[request.id] = nil }
        var state: CachedWindow
        if let cached = cache[request.id] {
            state = cached
        } else {
            if cache.count >= cacheLimit { cache.removeAll() }
            let settable = backend.settable(target.element)
            var current: CGRect?
            switch backend.frame(of: target.element) {
            case .success(let frame): current = frame
            case .failure(let failure) where failure == .invalidElement || failure == .apiDisabled
                || failure == .cannotComplete:
                return fail(failure, request)
            case .failure: current = nil
            }
            state = CachedWindow(movable: settable.movable, resizable: settable.resizable, lastWritten: current)
        }

        let frame = Self.wholePoints(request.frame)
        let needsSize = state.lastWritten?.size != frame.size
        // Some apps shift their window while resizing, so a resize re-anchors the origin.
        let needsPosition = state.lastWritten?.origin != frame.origin || (needsSize && state.movable)
        let writesSize = needsSize && state.resizable
        let writesPosition = needsPosition && state.movable
        if (needsSize || needsPosition) && !writesSize && !writesPosition {
            cache[request.id] = state
            return .failed(.rejected(L10n.text("windowkit.does.not.allow.this.window.to.be", String(describing: (target.appName)))))
        }
        if writesSize || writesPosition { suspendEnhancedUserInterface(pid: target.pid) }
        // Size first so windows with a minimum size keep their anchor; a move to another
        // display sets the size again, because the old display may have limited it.
        if writesSize, let failure = backend.setSize(frame.size, of: target.element) { return fail(failure, request) }
        if writesPosition, let failure = backend.setPosition(frame.origin, of: target.element) {
            return fail(failure, request)
        }
        if request.verify && writesSize && state.lastWritten?.origin != frame.origin,
           let failure = backend.setSize(frame.size, of: target.element) {
            return fail(failure, request)
        }
        var written = state.lastWritten ?? frame
        if writesSize { written.size = frame.size }
        if writesPosition { written.origin = frame.origin }
        state.lastWritten = written
        cache[request.id] = state
        guard request.verify else { return .written }

        let stamp = backend.nextStamp()
        let readback = backend.frame(of: target.element)
        restoreEnhancedUserInterface(pid: target.pid)
        switch readback {
        case .success(let actual):
            state.lastWritten = actual
            cache[request.id] = state
            return .settled(actual, stamp: stamp)
        case .failure(let failure):
            return fail(failure, request)
        }
    }

    /// Turns `AXEnhancedUserInterface` back on everywhere it was turned off.
    func restoreEnhancedUserInterface() {
        for pid in suspendedEnhanced { backend.setEnhancedUserInterface(true, pid: pid) }
        suspendedEnhanced.removeAll()
        checkedEnhanced.removeAll()
    }

    // Apps with the flag on (set by assistive tools, used by Chromium and Electron) animate
    // every Accessibility resize, which makes writes slow; it stays off until the job ends.
    private func suspendEnhancedUserInterface(pid: Int32) {
        guard checkedEnhanced.insert(pid).inserted, backend.enhancedUserInterface(pid: pid) == true else { return }
        backend.setEnhancedUserInterface(false, pid: pid)
        suspendedEnhanced.insert(pid)
    }

    private func restoreEnhancedUserInterface(pid: Int32) {
        checkedEnhanced.remove(pid)
        guard suspendedEnhanced.remove(pid) != nil else { return }
        backend.setEnhancedUserInterface(true, pid: pid)
    }

    /// Frames are written in whole points, as the legacy app did, so a fractional target
    /// reads back up to half a point away from it.
    private static func wholePoints(_ frame: CGRect) -> CGRect {
        CGRect(x: frame.minX.rounded(), y: frame.minY.rounded(), width: frame.width.rounded(), height: frame.height.rounded())
    }

    private func fail(_ failure: AXFailure, _ request: FrameWriter<Target>.Request) -> FrameWriteOutcome {
        cache[request.id] = nil
        restoreEnhancedUserInterface(pid: request.target.pid)
        return .failed(failure.windowError(id: request.id, pid: request.target.pid, appName: request.target.appName))
    }
}
