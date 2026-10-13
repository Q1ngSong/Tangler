import CoreGraphics
import Foundation

/// The app's only event tap (design section 2.2): active so it can swallow keys, at the head
/// of the session so it sees events first, and on its own thread so a busy main thread never
/// holds up input.
final class SystemEventTap: EventTapDriver, @unchecked Sendable {
    private static let eventTypes: [CGEventType] = [
        .keyDown, .keyUp, .flagsChanged,
        .leftMouseDown, .leftMouseDragged, .leftMouseUp,
        .rightMouseDown, .rightMouseDragged, .rightMouseUp,
        .otherMouseDown, .otherMouseDragged, .otherMouseUp,
        .mouseMoved, .scrollWheel,
    ]
    private static let eventMask = eventTypes.reduce(CGEventMask(0)) { $0 | CGEventMask(1) << CGEventMask($1.rawValue) }

    private struct Installed {
        let port: CFMachPort
        let thread: RunLoopThread
        let context: Unmanaged<TapContext>
    }

    private let lock = NSLock()
    private var installed: Installed?

    var isRunning: Bool {
        lock.withLock { installed.map { CGEvent.tapIsEnabled(tap: $0.port) } ?? false }
    }

    func canCreateTap() -> Bool {
        guard let port = Self.createTap(userInfo: nil) else { return false }
        CFMachPortInvalidate(port)
        return true
    }

    /// Callers serialize `start` and `stop`.
    func start(_ handler: EventTapHandler) -> Bool {
        if isRunning { return true }
        // A tap the system switched off for good, e.g. after the permission was revoked,
        // is replaced rather than reported as running.
        stop()
        let context = TapContext(handler: handler)
        let retained = Unmanaged.passRetained(context)
        guard let port = Self.createTap(userInfo: retained.toOpaque()) else {
            retained.release()
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            retained.release()
            return false
        }
        context.port = port
        let thread = RunLoopThread(name: "app.local.tangler.event-tap")
        thread.start(with: source)
        CGEvent.tapEnable(tap: port, enable: true)
        lock.withLock { installed = Installed(port: port, thread: thread, context: retained) }
        return isRunning
    }

    func stop() {
        let removed = lock.withLock { () -> Installed? in
            defer { installed = nil }
            return installed
        }
        guard let removed else { return }
        CGEvent.tapEnable(tap: removed.port, enable: false)
        // After the thread exits no callback can still be using the context.
        removed.thread.stop()
        CFMachPortInvalidate(removed.port)
        removed.context.release()
    }

    /// Created disabled, so no event waits on a tap whose run loop is not running yet.
    private static func createTap(userInfo: UnsafeMutableRawPointer?) -> CFMachPort? {
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                           options: .defaultTap, eventsOfInterest: eventMask,
                                           callback: tapCallback, userInfo: userInfo) else { return nil }
        CGEvent.tapEnable(tap: port, enable: false)
        return port
    }
}

/// What the C callback reaches through `userInfo`.
private final class TapContext {
    let handler: EventTapHandler
    /// Set before the tap's run loop starts, read only on the tap thread afterwards.
    var port: CFMachPort?

    init(handler: EventTapHandler) {
        self.handler = handler
    }

    /// Returns true to swallow the event.
    func process(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            handler.tapReenabled()
            return false
        case .mouseMoved where !handler.wantsMouseMoved():
            return false
        default:
            guard let raw = RawInputEvent(event, type: type) else { return false }
            return handler.handle(raw)
        }
    }
}

private func tapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                         userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let context = Unmanaged<TapContext>.fromOpaque(userInfo).takeUnretainedValue()
    return context.process(type, event) ? nil : Unmanaged.passUnretained(event)
}
