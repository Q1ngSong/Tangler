import CoreKit
import Contracts

/// How window errors and open outcomes read in reports and messages.
enum RestoreOutcomeText {
    static func text(for error: WindowError) -> String {
        switch error {
        case .notAuthorized: return L10n.text("workspaces.accessibility.access.is.missing.windows.cannot.be")
        case .windowNotFound: return L10n.text("switcher.the.window.has.closed")
        case .appNotResponding: return L10n.text("commandpalette.the.application.is.not.responding")
        case .rejected(let reason): return L10n.text("workspaces.the.window.rejected.this.position", String(describing: (reason)))
        case .unsupported(let reason): return reason
        }
    }

    /// Why a window operation failed, without the placement wording `text(for:)` adds.
    static func reason(_ error: WindowError) -> String {
        switch error {
        case .rejected(let reason), .unsupported(let reason): return reason
        case .notAuthorized, .windowNotFound, .appNotResponding: return text(for: error)
        }
    }

    /// Why opening failed; `launching` is a plain application launch, otherwise a document,
    /// folder or web page was being reopened.
    static func failure(_ outcome: OpenOutcome, launching: Bool) -> String {
        switch outcome {
        case .applicationNotFound: return L10n.text("workspaces.the.app.could.not.be.found")
        case .timedOut: return launching ? L10n.text("workspaces.the.system.did.not.respond.while.launching") : L10n.text("workspaces.the.system.did.not.respond.while.reopening")
        case .failed, .opened, .cancelled:
            return launching ? L10n.text("workspaces.could.not.launch.the.app") : L10n.text("workspaces.could.not.reopen.some.apps.require.automation")
        }
    }
}
