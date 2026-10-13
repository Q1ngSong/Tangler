import CoreKit
import Contracts

/// Why an Accessibility call failed, kept free of ApplicationServices types so the logic
/// around it can be tested without touching the real API.
enum AXFailure: Error, Equatable {
    case apiDisabled
    case cannotComplete
    case invalidElement
    case unsupported
    case other(Int32)

    func windowError(id: WindowID, pid: Int32, appName: String) -> WindowError {
        switch self {
        case .apiDisabled: return .notAuthorized
        case .cannotComplete: return .appNotResponding(pid: pid)
        case .invalidElement: return .windowNotFound(id)
        case .unsupported: return .rejected(L10n.text("windowkit.does.not.support.this.operation", String(describing: (appName))))
        case .other(let code): return .rejected(L10n.text("windowkit.accessibility.call.failed.error", String(describing: (code))))
        }
    }
}
