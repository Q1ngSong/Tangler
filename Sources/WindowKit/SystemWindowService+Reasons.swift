import Contracts

extension SystemWindowService {
    public func unavailableReason(for capability: WindowCapabilities) -> String? {
        WindowCapabilityStatus.unavailableReason(for: capability, available: capabilities, statuses: capabilityStatuses)
    }
}
