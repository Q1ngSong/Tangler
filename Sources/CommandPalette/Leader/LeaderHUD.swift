import Contracts
import CoreGraphics

/// The one heads-up panel the module owns: leader hints while leader mode runs, otherwise a
/// notice that hides itself after a moment.
@MainActor
final class LeaderHUD {
    var noticeSeconds = 2.5

    private let presenter: any LeaderPresenting
    private let scheduler: any Scheduling
    private var noticeTimer: ScheduledWork?
    private var isShowingHints = false

    init(presenter: any LeaderPresenting, scheduler: any Scheduling) {
        self.presenter = presenter
        self.scheduler = scheduler
    }

    func showHints(_ hints: LeaderHints, in area: CGRect) {
        noticeTimer?.cancel()
        noticeTimer = nil
        isShowingHints = true
        presenter.show(.hints(hints), in: area)
    }

    /// Ignored while hints are up, so a late result never covers a new leader session.
    func showNotice(_ notice: LeaderNotice, in area: CGRect) {
        guard !isShowingHints else { return }
        noticeTimer?.cancel()
        presenter.show(.notice(notice), in: area)
        noticeTimer = scheduler.schedule(after: noticeSeconds) { [weak self] in self?.hide() }
    }

    /// Says why a command run from the leader or the palette did nothing.
    func report(_ result: CommandResult, title: String?, in area: CGRect) {
        switch result {
        case .done:
            break
        case .unavailable(let reason), .failed(let reason):
            showNotice(LeaderNotice(title: title, message: reason), in: area)
        }
    }

    func hide() {
        noticeTimer?.cancel()
        noticeTimer = nil
        isShowingHints = false
        presenter.hide()
    }
}
