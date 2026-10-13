import ApplicationServices

/// The accessibility observer on the Dock's application element for `ExposeSignal.names`. Its
/// callbacks arrive with the window notifications, on the backend's thread. Not thread safe:
/// `ExposeWatcher` calls it one at a time.
final class ExposeObserver {
    private let backend: AXObserverBackend
    private var observation: AXObserverBackend.Observation?

    init(backend: AXObserverBackend) {
        self.backend = backend
    }

    /// Observes the Dock `pid` instead of whatever was observed before. Anything short of every
    /// notification registered observes nothing.
    func attach(pid: Int32) -> RegistrationResult {
        detach()
        // No observer: the backend is stopped, or the Dock is not ready for one yet.
        guard let observation = backend.makeObserver(pid: pid) else { return .retryLater }
        let result = backend.register(ExposeSignal.names, onApplication: pid, with: observation)
        if result == .registered {
            self.observation = observation
        } else {
            backend.retire(observation)
        }
        return result
    }

    func detach() {
        guard let observation else { return }
        backend.retire(observation)
        self.observation = nil
    }
}
