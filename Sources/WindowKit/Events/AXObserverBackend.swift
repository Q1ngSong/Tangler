import ApplicationServices
import Foundation

/// The observer hub's calls through Accessibility. Callbacks arrive on a dedicated run loop
/// thread and go straight to `deliver`.
final class AXObserverBackend: ObserverBackend, @unchecked Sendable {
    typealias Deliver = (_ pid: Int32, _ notification: String, _ element: AXUIElement) -> Void

    final class Context {
        let pid: Int32
        let deliver: Deliver

        init(pid: Int32, deliver: @escaping Deliver) {
            self.pid = pid
            self.deliver = deliver
        }
    }

    final class Observation {
        let observer: AXObserver
        let context: Context

        init(observer: AXObserver, context: Context) {
            self.observer = observer
            self.context = context
        }

        var refcon: UnsafeMutableRawPointer { Unmanaged.passUnretained(context).toOpaque() }
    }

    private let deliver: Deliver
    private let lock = NSLock()
    private var thread: RunLoopThread?
    private var loop: CFRunLoop?

    init(deliver: @escaping Deliver) {
        self.deliver = deliver
    }

    func start() {
        locked {
            guard thread == nil else { return }
            let thread = RunLoopThread()
            thread.name = "app.local.tangler.ax-observers"
            thread.qualityOfService = .userInitiated
            loop = thread.startLoop()
            self.thread = thread
        }
    }

    func stop() {
        let thread = locked { () -> RunLoopThread? in
            defer { self.thread = nil; loop = nil }
            return self.thread
        }
        thread?.stopLoop()
    }

    func makeObserver(pid: Int32) -> Observation? {
        locked {
            guard let loop else { return nil }
            var observer: AXObserver?
            guard AXObserverCreate(pid, observerCallback, &observer) == .success, let observer else { return nil }
            CFRunLoopAddSource(loop, AXObserverGetRunLoopSource(observer), .defaultMode)
            return Observation(observer: observer, context: Context(pid: pid, deliver: deliver))
        }
    }

    // Removing the source on the callback thread means no callback can still be using the
    // context when the observation is released.
    func retire(_ observation: Observation) {
        guard let thread = locked({ thread }) else { return }
        thread.perform {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observation.observer), .defaultMode)
            withExtendedLifetime(observation) {}
        }
    }

    func registerApplication(_ pid: Int32, with observation: Observation) -> RegistrationResult {
        register(WindowNotification.applicationNotifications, onApplication: pid, with: observation)
    }

    /// Registers notifications on the application element itself, also ones that are not about
    /// windows, such as the Dock's about Exposé.
    func register(_ names: [String], onApplication pid: Int32, with observation: Observation) -> RegistrationResult {
        let application = AXRead.application(pid)
        return Self.result(of: names.map { name in
            AXObserverAddNotification(observation.observer, application, name as CFString, observation.refcon)
        })
    }

    func register(_ window: AXHandle, with observation: Observation) -> RegistrationResult {
        AXUIElementSetMessagingTimeout(window.element, AXRead.timeout)
        return Self.result(of: WindowNotification.windowNotifications.map { name in
            AXObserverAddNotification(observation.observer, window.element, name as CFString, observation.refcon)
        })
    }

    func unregister(_ window: AXHandle, with observation: Observation) {
        for name in WindowNotification.windowNotifications {
            AXObserverRemoveNotification(observation.observer, window.element, name as CFString)
        }
    }

    /// One registration's errors, one per notification. A notification the element does not
    /// support counts as done: some windows, for example, cannot be minimized.
    static func result(of errors: [AXError]) -> RegistrationResult {
        if errors.contains(where: { [.invalidUIElement, .invalidUIElementObserver, .apiDisabled].contains($0) }) {
            return .abandoned
        }
        return errors.contains(where: { $0 == .cannotComplete || $0 == .failure }) ? .retryLater : .registered
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private let observerCallback: AXObserverCallback = { _, element, notification, refcon in
    guard let refcon else { return }
    let context = Unmanaged<AXObserverBackend.Context>.fromOpaque(refcon).takeUnretainedValue()
    context.deliver(context.pid, notification as String, element)
}
