import CoreKit

/// Where a desktop operation says what the user should know and no result carries, such as a
/// temporary desktop left behind (workspaces design 7.5): always the diagnostic log, and whoever
/// the service was told to tell.
final class DesktopReports: Sendable {
    let handler = Locked<(@Sendable (String) -> Void)?>(nil)
    private let log: @Sendable (String) -> Void

    init(log: @escaping @Sendable (String) -> Void = { DiagnosticLog("desktops").problem($0) }) {
        self.log = log
    }

    func send(_ message: String) {
        log(message)
        handler.value?(message)
    }
}
