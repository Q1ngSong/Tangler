import Contracts

/// Finds the capturable window for a window ID. Listing shareable content is slow, so the
/// list is reused for `lifetime` and concurrent callers share one load.
actor WindowLookup {
    typealias Load = @Sendable () async throws -> [any CapturableWindow]

    private let lifetime: Duration
    private let now: @Sendable () -> ContinuousClock.Instant
    private let load: Load
    private var windows: [WindowID: any CapturableWindow] = [:]
    private var loadedAt: ContinuousClock.Instant?
    private var loading: Task<Void, Never>?

    init(lifetime: Duration = .seconds(1), now: @escaping @Sendable () -> ContinuousClock.Instant, load: @escaping Load) {
        self.lifetime = lifetime
        self.now = now
        self.load = load
    }

    func window(_ id: WindowID) async -> (any CapturableWindow)? {
        var reloaded = false
        if !isFresh {
            await reload()
            reloaded = true
        }
        if let window = windows[id] { return window }
        // A cached list may predate the window, so a miss earns one fresh look.
        guard !reloaded else { return nil }
        await reload()
        return windows[id]
    }

    private var isFresh: Bool {
        guard let loadedAt else { return false }
        return now() - loadedAt < lifetime
    }

    private func reload() async {
        if let loading { return await loading.value }
        let task = Task {
            let list = try? await load()
            windows = Dictionary((list ?? []).map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
            loadedAt = list == nil ? nil : now()
            loading = nil
        }
        loading = task
        await task.value
    }
}
