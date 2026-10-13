import CoreKit
import Contracts
import Foundation

/// Decides which private abilities to use: a symbol must exist, and where a harmless call
/// is possible it must answer as expected (design section 5.2).
enum CapabilityProbe {
    struct Environment {
        var hasSymbol: (PrivateSymbol) -> Bool
        /// The main window server connection is nonzero.
        var connectionAnswers: () -> Bool
        /// The Space list comes back as an array.
        var spaceListAnswers: () -> Bool
        /// An element can be built from a remote token for this process.
        var remoteTokenAnswers: () -> Bool
        /// The bridged move operation class has the expected methods and signatures.
        var moveOperationMatches: () -> Bool
        var systemVersion: OperatingSystemVersion
        var screensHaveSeparateSpaces: Bool
    }

    static func probe(_ environment: Environment) -> [WindowCapabilityStatus] {
        func has(_ symbols: PrivateSymbol...) -> Bool { symbols.allSatisfy(environment.hasSymbol) }

        let exactIDs = has(.windowForElement)
        let exactIDsReason: String? = exactIDs ? nil : "windowkit.private.api.unavailable.matching.windows.by.process"

        let otherSpacesReason: String?
        if !exactIDs {
            otherSpacesReason = "windowkit.exact.window.ids.are.required.only.current"
        } else if !has(.elementWithRemoteToken) || !environment.remoteTokenAnswers() {
            otherSpacesReason = "windowkit.private.api.unavailable.only.current.desktop.and"
        } else {
            otherSpacesReason = nil
        }

        let spaceListReason: String?
        if !has(.mainConnection, .managedDisplaySpaces) {
            spaceListReason = "windowkit.private.api.unavailable.cannot.read.the.desktop"
        } else if !environment.connectionAnswers() || !environment.spaceListAnswers() {
            spaceListReason = "windowkit.the.window.server.did.not.return.a"
        } else {
            spaceListReason = nil
        }

        let noSpaceList = "windowkit.cannot.read.the.desktop.list"
        let needsSeparateSpaces = "windowkit.enable.displays.have.separate.spaces.in.system"

        let moveReason: String?
        if !environment.systemVersion.isAtLeast(major: 26, minor: 4) {
            moveReason = "windowkit.requires.macos.or.later"
        } else if spaceListReason != nil {
            moveReason = noSpaceList
        } else if !environment.screensHaveSeparateSpaces {
            moveReason = needsSeparateSpaces
        } else if !has(.spacesForWindows) || !environment.moveOperationMatches() {
            moveReason = "windowkit.the.system.does.not.provide.an.api"
        } else {
            moveReason = nil
        }

        let focusReason: String? = has(.setFrontProcess, .postEventRecord, .processForPID) ? nil
            : "windowkit.private.api.unavailable.activating.the.app.before"

        // Mission Control's own controls can only be read while it is open, and the Dock may be
        // restarting at launch, so neither is probed: an operation that cannot open Mission
        // Control says so when it is asked.
        let manageReason: String?
        if spaceListReason != nil {
            manageReason = noSpaceList
        } else if !environment.screensHaveSeparateSpaces {
            manageReason = needsSeparateSpaces
        } else if !has(.dockNotification) {
            manageReason = "windowkit.the.system.does.not.provide.an.api.capabilityprobe"
        } else if !has(.spacesForWindows) {
            // Going to an empty desktop adds a temporary one, which is only removed once it is
            // known to hold no window: without this it would be left behind every time.
            manageReason = "windowkit.the.system.cannot.report.window.desktop.membership"
        } else {
            manageReason = nil
        }

        return [
            status(.exactWindowIDs, "windowkit.exact.window.ids", exactIDsReason),
            status(.otherSpaceWindows, "windowkit.windows.on.other.desktops", otherSpacesReason),
            status(.spaceList, "windowkit.desktop.list", spaceListReason),
            status(.moveAcrossSpaces, "windowkit.move.to.another.desktop", moveReason),
            status(.preciseFocus, "windowkit.precise.window.focus", focusReason),
            status(.manageSpaces, "windowkit.create.and.remove.desktops", manageReason),
        ]
    }

    static func capabilities(of statuses: [WindowCapabilityStatus]) -> WindowCapabilities {
        statuses.filter(\.isAvailable).reduce(into: WindowCapabilities()) { $0.insert($1.capability) }
    }

    /// Retain localization keys without probing the system again when the language changes.
    private static func status(_ capability: WindowCapabilities, _ name: String, _ reason: String?) -> WindowCapabilityStatus {
        WindowCapabilityStatus(capability: capability, nameKey: name, reasonKey: reason)
    }
}

private extension OperatingSystemVersion {
    func isAtLeast(major: Int, minor: Int) -> Bool {
        majorVersion > major || (majorVersion == major && minorVersion >= minor)
    }
}
