import CoreKit
import Contracts

/// Text the user reads: notes on the panel and the settings page, and why a switch failed.
enum SwitcherText {
    static var needsAccessibility: String { L10n.text("switcher.accessibility.access.is.required.to.switch.windows") }
    static var noWindows: String { L10n.text("switcher.no.windows.available.to.switch.to") }
    static var noAppWindows: String { L10n.text("switcher.the.current.app.has.no.windows.available") }
    static var noScreenRecording: String { L10n.text("dockpreview.enable.screen.recording.to.show.thumbnails") }
    static var systemSwitcherMayAppear: String { L10n.text("switcher.the.system.tab.switcher.could.not.be") }
    static var stopped: String { L10n.text("switcher.the.switcher.has.stopped") }

    static func currentSpaceOnly(reason: String?) -> String {
        reason.map { L10n.text("switcher.only.windows.on.the.current.desktop.are", String(describing: ($0))) } ?? L10n.text("dockpreview.only.windows.on.the.current.desktop.are")
    }

    static func reason(for error: WindowError) -> String {
        switch error {
        case .notAuthorized: return needsAccessibility
        case .windowNotFound: return L10n.text("switcher.the.window.has.closed")
        case .appNotResponding: return L10n.text("commandpalette.the.application.is.not.responding")
        case .rejected(let reason), .unsupported(let reason): return reason
        }
    }
}
