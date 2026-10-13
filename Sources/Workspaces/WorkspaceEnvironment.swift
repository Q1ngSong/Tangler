import Foundation

/// What the module uses besides `ModuleContext`; tests replace all of it.
@MainActor
struct WorkspaceEnvironment {
    var opener: any ApplicationOpening
    var timing: RestoreTiming
    var notifier: any WorkspaceNotifying
    var clock: AutoSaveClock
    /// The date, for when checkpoints were saved and workspaces deleted.
    var now: () -> Date

    init(opener: any ApplicationOpening, timing: RestoreTiming = RestoreTiming(), notifier: any WorkspaceNotifying,
         clock: AutoSaveClock = .system, now: @escaping () -> Date = Date.init) {
        self.opener = opener
        self.timing = timing
        self.notifier = notifier
        self.clock = clock
        self.now = now
    }

    /// NSWorkspace for opening and a HUD for reports.
    static func system() -> WorkspaceEnvironment {
        WorkspaceEnvironment(opener: ApplicationOpener(), notifier: HUDNotifier())
    }
}
