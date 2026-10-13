import Contracts
import Foundation
import Observation

/// Keeps the slider and preview live, but saves height only after a short pause. The module
/// observes saved settings, so heights passed over while dragging never become window writes.
@MainActor
@Observable
final class TabGroupsSettingsModel {
    static let heightQuietInterval: TimeInterval = 0.15

    private var draft: TabGroupsSettings
    @ObservationIgnored private var saved: TabGroupsSettings
    @ObservationIgnored private let store: any SettingsStore
    @ObservationIgnored private let scheduler: any TabScheduler
    @ObservationIgnored private var heightWork: TabScheduledWork?

    init(store: any SettingsStore, scheduler: (any TabScheduler)? = nil) {
        self.store = store
        self.scheduler = scheduler ?? SystemTabScheduler()
        var settings = store.load(TabGroupsSettings.self)
        settings.barHeight = Double(settings.effectiveBarHeight)
        draft = settings
        saved = settings
    }

    var settings: TabGroupsSettings {
        get { draft }
        set {
            guard newValue != draft else { return }
            let heightChanged = newValue.barHeight != draft.barHeight
            draft = newValue
            // Toggles remain immediate without accidentally committing a height in flight.
            var immediate = newValue
            immediate.barHeight = saved.barHeight
            save(immediate)
            guard heightChanged else { return }
            heightWork?.cancel()
            heightWork = nil
            guard draft.barHeight != saved.barHeight else { return }
            heightWork = scheduler.schedule(at: scheduler.now + Self.heightQuietInterval) { [weak self] in
                self?.flush()
            }
        }
    }

    /// Leaving the page keeps the final selection and cancels its now-unnecessary timer.
    func flush() {
        heightWork?.cancel()
        heightWork = nil
        save(draft)
    }

    private func save(_ settings: TabGroupsSettings) {
        guard settings != saved else { return }
        saved = settings
        store.save(settings)
    }
}
