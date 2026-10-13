import CoreKit
import Contracts

/// One private ability and whether this Mac offers it, for the App's diagnostics page.
public struct WindowCapabilityStatus: Equatable, Sendable {
    /// A single capability flag.
    public let capability: WindowCapabilities
    private let fallbackName: String
    private let nameKey: String?
    public var name: String { nameKey.map { L10n.text($0) } ?? fallbackName }
    public let isAvailable: Bool
    private let fallbackReason: String?
    private let reasonKey: String?
    /// Why the ability is unavailable and what replaces it; nil when available.
    public var reason: String? { reasonKey.map { L10n.text($0) } ?? fallbackReason }

    public init(capability: WindowCapabilities, name: String, isAvailable: Bool, reason: String?) {
        self.capability = capability
        self.fallbackName = name
        self.nameKey = nil
        self.isAvailable = isAvailable
        self.fallbackReason = reason
        self.reasonKey = nil
    }

    init(capability: WindowCapabilities, nameKey: String, reasonKey: String?) {
        self.capability = capability
        self.nameKey = nameKey
        self.reasonKey = reasonKey
        fallbackName = ""
        fallbackReason = nil
        isAvailable = reasonKey == nil
    }
}

extension WindowCapabilityStatus {
    /// Why `capability` is unavailable, joined from the probed reasons; nil when every flag
    /// in it is available.
    static func unavailableReason(for capability: WindowCapabilities, available: WindowCapabilities,
                                  statuses: [WindowCapabilityStatus]) -> String? {
        guard !available.isSuperset(of: capability) else { return nil }
        let reasons = statuses.filter { capability.contains($0.capability) && !$0.isAvailable }.compactMap(\.reason)
        return reasons.isEmpty ? L10n.text("windowkit.unavailable.on.this.mac") : reasons.joined(separator: L10n.text("text.reasonSeparator"))
    }
}
