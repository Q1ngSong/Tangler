import Foundation

/// How registering notifications with an app went.
enum RegistrationResult: Equatable {
    case registered
    /// The app did not answer in time, e.g. while it launches; worth another try.
    case retryLater
    /// The element is gone or Accessibility is off; another try cannot help.
    case abandoned
}

enum RegistrationBackoff {
    /// The pause before trying again after try number `attempt` (from 0) failed: 0.5 seconds,
    /// doubling up to 32.
    static func pause(after attempt: Int) -> Double { 0.5 * Double(1 << min(max(attempt, 0), 6)) }
}

/// The Accessibility calls the observer hub makes, injectable so its bookkeeping can be tested.
protocol ObserverBackend: AnyObject {
    associatedtype Window: Hashable
    associatedtype Observer: AnyObject

    /// Starts and stops delivering callbacks.
    func start()
    func stop()
    /// A new observer delivering `pid`'s notifications; nil when stopped or when the app
    /// cannot be observed.
    func makeObserver(pid: Int32) -> Observer?
    /// Ends delivery from `observer` once any callback in progress has returned.
    func retire(_ observer: Observer)
    func registerApplication(_ pid: Int32, with observer: Observer) -> RegistrationResult
    func register(_ window: Window, with observer: Observer) -> RegistrationResult
    func unregister(_ window: Window, with observer: Observer)
}

/// One observer per application, with window notifications registered for the windows the
/// inventory lists. Registrations are synchronous round trips to the app, so they run on
/// their own queue, where a slow app delays nobody's callbacks. A registration the app did
/// not answer in time is tried again after a growing pause, by a timer and by the next sync,
/// so a window that appeared while its app was busy still reports moves and closes.
final class ObserverHub<Backend: ObserverBackend>: @unchecked Sendable {
    typealias Window = Backend.Window

    /// Guarded by the hub's lock.
    private final class Record {
        let pid: Int32
        let observer: Backend.Observer
        /// The windows the inventory wants observed.
        var wanted: Set<Window> = []
        /// Wanted windows with notifications registered, or with a registration on the way.
        var windows: Set<Window> = []
        /// Wanted windows whose registration failed: how often, and when to try again.
        var failures: [Window: (count: Int, retryAt: Double)] = [:]

        init(pid: Int32, observer: Backend.Observer) {
            self.pid = pid
            self.observer = observer
        }

        /// Not registered, nor waiting out a pause after a failure.
        func isDue(_ window: Window, at now: Double) -> Bool {
            !windows.contains(window) && failures[window].map { $0.retryAt <= now } ?? true
        }
    }

    private let backend: Backend
    private let retryDelay: (_ attempt: Int) -> Double
    private let now: () -> Double
    private let registrations = DispatchQueue(label: "app.local.tangler.ax-registration", qos: .utility)
    private let lock = NSLock()
    private var isStarted = false
    private var records: [Int32: Record] = [:]

    /// `retryDelay` is the pause before trying again after try number `attempt` (from 0)
    /// failed. `now` reads the clock in seconds.
    init(backend: Backend,
         retryDelay: @escaping (_ attempt: Int) -> Double = RegistrationBackoff.pause(after:),
         now: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.backend = backend
        self.retryDelay = retryDelay
        self.now = now
    }

    var attachedPIDs: Set<Int32> { locked { Set(records.keys) } }

    func start() {
        locked {
            guard !isStarted else { return }
            backend.start()
            isStarted = true
        }
    }

    func stop() {
        // Marked stopped first, so no app is attached between detaching and stopping.
        let wasStarted = locked { () -> Bool in
            defer { isStarted = false }
            return isStarted
        }
        detachAll()
        if wasStarted { backend.stop() }
    }

    func attach(pid: Int32) {
        let record = locked { () -> Record? in
            guard isStarted, records[pid] == nil, let observer = backend.makeObserver(pid: pid) else { return nil }
            let record = Record(pid: pid, observer: observer)
            records[pid] = record
            return record
        }
        guard let record else { return }
        registrations.async { [weak self] in self?.registerApplication(record, attempt: 0) }
    }

    func detach(pid: Int32) {
        guard let record = locked({ records.removeValue(forKey: pid) }) else { return }
        backend.retire(record.observer)
    }

    func detachAll() {
        let all = locked { () -> [Record] in
            defer { records.removeAll() }
            return Array(records.values)
        }
        for record in all { backend.retire(record.observer) }
    }

    /// Registers window notifications for new windows of `pid`, and for windows whose
    /// registration failed once their pause is over, and drops them for windows gone.
    func sync(pid: Int32, windows: [Window]) {
        let now = self.now()
        let change = locked { () -> (record: Record, added: [Window], removed: [Window])? in
            guard let record = records[pid] else { return nil }
            record.wanted = Set(windows)
            record.failures = record.failures.filter { record.wanted.contains($0.key) }
            let added = record.wanted.filter { record.isDue($0, at: now) }
            let removed = record.windows.subtracting(record.wanted)
            record.windows = record.windows.intersection(record.wanted).union(added)
            return (record, Array(added), Array(removed))
        }
        guard let change, !change.added.isEmpty || !change.removed.isEmpty else { return }
        registrations.async { [weak self] in
            guard let self, self.isCurrent(change.record) else { return }
            change.added.forEach { self.register($0, in: change.record) }
            change.removed.forEach { self.backend.unregister($0, with: change.record.observer) }
        }
    }

    func observe(_ window: Window, pid: Int32) {
        let now = self.now()
        let record = locked { () -> Record? in
            guard let record = records[pid] else { return nil }
            record.wanted.insert(window)
            guard record.isDue(window, at: now) else { return nil }
            record.windows.insert(window)
            return record
        }
        guard let record else { return }
        registrations.async { [weak self] in
            guard let self, self.isCurrent(record) else { return }
            self.register(window, in: record)
        }
    }

    func forget(_ window: Window, pid: Int32) {
        let record = locked { () -> Record? in
            guard let record = records[pid] else { return nil }
            record.wanted.remove(window)
            record.failures[window] = nil
            guard record.windows.remove(window) != nil else { return nil }
            return record
        }
        guard let record else { return }
        registrations.async { [weak self] in self?.backend.unregister(window, with: record.observer) }
    }

    /// Asked again for as long as the app runs: a freshly launched or busy app may not answer
    /// for a while, and without these notifications its new windows go unnoticed.
    private func registerApplication(_ record: Record, attempt: Int) {
        guard isCurrent(record), backend.registerApplication(record.pid, with: record.observer) == .retryLater else { return }
        registrations.asyncAfter(deadline: .now() + retryDelay(attempt)) { [weak self] in
            self?.registerApplication(record, attempt: attempt + 1)
        }
    }

    /// Runs on the registrations queue.
    private func register(_ window: Window, in record: Record) {
        let result = backend.register(window, with: record.observer)
        let failure = locked { () -> (count: Int, pause: Double)? in
            guard result == .retryLater, record.wanted.contains(window) else {
                record.failures[window] = nil
                return nil
            }
            // Not counted as observed, so a sync after the pause tries again too.
            record.windows.remove(window)
            let count = (record.failures[window]?.count ?? 0) + 1
            let pause = retryDelay(count - 1)
            record.failures[window] = (count, now() + pause)
            return (count, pause)
        }
        guard let failure else { return }
        registrations.asyncAfter(deadline: .now() + failure.pause) { [weak self] in
            self?.retry(window, in: record, afterFailure: failure.count)
        }
    }

    private func retry(_ window: Window, in record: Record, afterFailure count: Int) {
        let due = locked { () -> Bool in
            // Skipped when a sync tried meanwhile: a newer failure has a timer of its own.
            guard records[record.pid] === record, record.wanted.contains(window), !record.windows.contains(window),
                  record.failures[window]?.count == count else { return false }
            record.windows.insert(window)
            return true
        }
        if due { register(window, in: record) }
    }

    private func isCurrent(_ record: Record) -> Bool {
        locked { records[record.pid] === record }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
