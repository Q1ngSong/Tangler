import Contracts
import CoreGraphics

/// The leader hint panel's content.
struct LeaderHints: Equatable {
    var options: [LeaderOption]
    /// The group typed so far, or the command that just ran.
    var title: String?
    var footer: String?
    /// Lingering after a command: still listening, but out of the way.
    var isFaded: Bool
}

/// A short message, e.g. why a command could not run.
struct LeaderNotice: Equatable {
    var title: String?
    var message: String
}

enum LeaderOverlay: Equatable {
    case hints(LeaderHints)
    case notice(LeaderNotice)
}

/// Puts the leader overlay on screen; tests record it instead.
@MainActor
protocol LeaderPresenting: AnyObject {
    /// Shows `overlay` centered in `area` (global coordinates), replacing what was shown.
    func show(_ overlay: LeaderOverlay, in area: CGRect)
    func hide()
}
