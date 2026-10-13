import Foundation

/// The time automatic saving goes by. Injected, so tests never really wait.
struct AutoSaveClock: Sendable {
    /// The time since a fixed moment.
    var now: @Sendable () -> Duration
    var sleep: @Sendable (Duration) async throws -> Void

    static let system: AutoSaveClock = {
        let start = ContinuousClock.now
        return AutoSaveClock(now: { ContinuousClock.now - start }, sleep: { try await Task.sleep(for: $0) })
    }()
}

/// When a checkpoint may be saved without being asked (workspaces design section 14, the notes
/// of 2026-10-11): the timer, the one save a workspace has under way, and the times of its last
/// save and expansion. The controller says what to save and does the saving.
@MainActor
final class CheckpointAutoSaver {
    /// How long a workspace is left alone after an open or revert of it ended, so a desktop
    /// whose windows are still arriving does not become the checkpoint.
    static let settling: Duration = .seconds(10)

    private let clock: AutoSaveClock
    private var timer: Task<Void, Never>?
    private var saves: [UUID: (token: UUID, task: Task<Bool, Never>)] = [:]
    private var savedAt: [UUID: Duration] = [:]
    private var expansions: [UUID: Int] = [:]
    private var expandedAt: [UUID: Duration] = [:]

    var savesUnderWay: [Task<Bool, Never>] { saves.values.map(\.task) }

    init(clock: AutoSaveClock) {
        self.clock = clock
    }

    /// Calls `tick` every `interval` from now on, in place of what was scheduled. A tick is over
    /// before the next wait begins.
    func schedule(every interval: Duration, _ tick: @escaping @MainActor () async -> Void) {
        timer?.cancel()
        timer = Task { [clock] in
            while (try? await clock.sleep(interval)) != nil, !Task.isCancelled {
                await tick()
            }
        }
    }

    func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    func expansionBegan(_ id: UUID) {
        expansions[id, default: 0] += 1
    }

    func expansionEnded(_ id: UUID) {
        expansions[id] = expansions[id].flatMap { $0 > 1 ? $0 - 1 : nil }
        expandedAt[id] = clock.now()
    }

    /// True while the workspace is expanded and for `settling` afterwards.
    func isSettling(_ id: UUID) -> Bool {
        if expansions[id] != nil { return true }
        return expandedAt[id].map { clock.now() - $0 < Self.settling } ?? false
    }

    /// Any save counts, also the ones the user asked for.
    func noteSaved(_ id: UUID) {
        savedAt[id] = clock.now()
    }

    func wasSaved(_ id: UUID, within time: Duration) -> Bool {
        savedAt[id].map { clock.now() - $0 < time } ?? false
    }

    /// The workspace was deleted: its times are dropped.
    func forget(_ id: UUID) {
        savedAt[id] = nil
        expandedAt[id] = nil
    }

    /// Starts `save` for the workspace and returns it; the save already under way when there is
    /// one, and nil while the workspace is settling.
    func save(_ id: UUID, _ save: @escaping @MainActor () async -> Bool) -> Task<Bool, Never>? {
        if let running = saves[id] { return running.task }
        guard !isSettling(id) else { return nil }
        let token = UUID()
        let task = Task { [weak self] in
            let saved = await save()
            if saved { self?.noteSaved(id) }
            if self?.saves[id]?.token == token { self?.saves[id] = nil }
            return saved
        }
        saves[id] = (token, task)
        return task
    }

    /// Ends the timer and cancels the saves under way, which then write nothing.
    func stop() {
        stopTimer()
        for save in saves.values { save.task.cancel() }
        saves = [:]
    }
}
