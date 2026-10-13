import Contracts
import Foundation

/// Reads the per-display Space list the window server reports (see `Private/PrivateSpaces`).
enum SpaceParser {
    private static let desktopType = 0
    private static let fullscreenType = 4
    /// The display identifier used when all displays share one set of Spaces.
    private static let sharedDisplay = "Main"

    /// Desktops are numbered 1...n on each display, like the "Desktop N" labels in Mission
    /// Control; fullscreen Spaces are numbered separately so they never shift desktop numbers.
    static func spaces(from displays: [[String: Any]], mainDisplayID: DisplayID?) -> [SpaceInfo] {
        var result: [SpaceInfo] = []
        var seen = Set<UInt64>()
        for display in displays {
            guard let identifier = display["Display Identifier"] as? String,
                  let entries = display["Spaces"] as? [[String: Any]] else { continue }
            let displayID = identifier == sharedDisplay ? mainDisplayID ?? DisplayID(rawValue: identifier)
                : DisplayID(rawValue: identifier)
            let current = (display["Current Space"] as? [String: Any]).flatMap(spaceID)
            var desktops = 0
            var fullscreens = 0
            for entry in entries {
                guard let id = spaceID(entry), let type = (entry["type"] as? NSNumber)?.intValue,
                      type == desktopType || type == fullscreenType, seen.insert(id).inserted else { continue }
                let isFullscreen = type == fullscreenType
                if isFullscreen { fullscreens += 1 } else { desktops += 1 }
                result.append(SpaceInfo(id: SpaceID(rawValue: id), displayID: displayID,
                                        index: isFullscreen ? fullscreens : desktops, isCurrent: id == current,
                                        isFullscreen: isFullscreen,
                                        uuid: (entry["uuid"] as? String).flatMap { $0.isEmpty ? nil : $0 }))
            }
        }
        return result
    }

    private static func spaceID(_ entry: [String: Any]) -> UInt64? {
        ((entry["ManagedSpaceID"] ?? entry["id64"]) as? NSNumber)?.uint64Value
    }
}
