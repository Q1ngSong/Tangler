import Foundation

/// The capability probe's environment on this Mac. The harmless calls make no request of
/// any other application and change nothing.
enum LiveProbe {
    static func environment() -> CapabilityProbe.Environment {
        let displaySpaces = PrivateSpaces()?.displaySpaces()
        let spansDisplays = CFPreferencesCopyAppValue("spans-displays" as CFString, "com.apple.spaces" as CFString) as? Bool
        return CapabilityProbe.Environment(
            hasSymbol: { PrivateSymbols.address(of: $0) != nil },
            connectionAnswers: { (PrivateSpaces.connectionID() ?? 0) != 0 },
            spaceListAnswers: { displaySpaces != nil },
            remoteTokenAnswers: { RemoteWindowFinder.canBuildElements() },
            moveOperationMatches: { SpaceMover.operationMatches() },
            systemVersion: ProcessInfo.processInfo.operatingSystemVersion,
            screensHaveSeparateSpaces: SeparateSpaces.isOn(
                displayIdentifiers: displaySpaces?.compactMap { $0["Display Identifier"] as? String },
                spansDisplaysPreference: spansDisplays))
    }
}
