import os

/// Tangler's trace in the unified log: subsystem `app.local.tangler`, one category per module.
///
/// `trace` is for every event and is debug level, which the system keeps only while someone
/// watches, e.g. `scripts/trace.sh`. `note` is for rare state changes and `problem` for
/// failures; both stay in the log for `log show`. Never log what the user types: modifier
/// keys, matched shortcuts and command names only.
public struct DiagnosticLog: Sendable {
    public static let subsystem = "app.local.tangler"
    private let logger: Logger

    public init(_ category: String) {
        logger = Logger(subsystem: Self.subsystem, category: category)
    }

    public func trace(_ message: @autoclosure () -> String) {
        let text = message()
        logger.debug("\(text, privacy: .public)")
    }

    public func note(_ message: @autoclosure () -> String) {
        let text = message()
        logger.notice("\(text, privacy: .public)")
    }

    public func problem(_ message: @autoclosure () -> String) {
        let text = message()
        logger.error("\(text, privacy: .public)")
    }
}
