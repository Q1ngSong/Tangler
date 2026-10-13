import CoreKit
import Contracts

/// Why switching to a window failed, in words for a notice.
enum WindowErrorText {
    static func describe(_ error: WindowError) -> String {
        switch error {
        case .notAuthorized: return L10n.text("commandpalette.accessibility.access.is.required")
        case .windowNotFound: return L10n.text("commandpalette.this.window.has.closed")
        case .appNotResponding: return L10n.text("commandpalette.the.application.is.not.responding")
        case .rejected(let reason), .unsupported(let reason): return reason
        }
    }
}
