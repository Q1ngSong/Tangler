import Contracts
import Foundation

/// Space queries through SkyLight. Without them WindowKit reports no Spaces and windows carry
/// empty `spaceIDs` (design section 5.2).
struct PrivateSpaces: @unchecked Sendable {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CopySpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    /// Current, other and user Spaces: every Space a window can be on.
    private static let allSpacesMask: Int32 = 0x7

    private let connection: Int32
    private let copyDisplaySpaces: CopyManagedDisplaySpaces
    private let copySpacesForWindows: CopySpacesForWindows?

    init?() {
        guard let connection = Self.connectionID(), connection != 0,
              let copy = PrivateSymbols.function(.managedDisplaySpaces, as: CopyManagedDisplaySpaces.self) else { return nil }
        self.connection = connection
        copyDisplaySpaces = copy
        copySpacesForWindows = PrivateSymbols.function(.spacesForWindows, as: CopySpacesForWindows.self)
    }

    static func connectionID() -> Int32? {
        PrivateSymbols.function(.mainConnection, as: MainConnection.self).map { $0() }
    }

    /// Each display's Spaces as the window server reports them; nil when it does not answer.
    func displaySpaces() -> [[String: Any]]? {
        copyDisplaySpaces(connection)?.takeRetainedValue() as? [[String: Any]]
    }

    /// The Spaces showing a window; nil when membership cannot be read.
    func spaceIDs(of id: WindowID) -> [SpaceID]? {
        guard let copySpacesForWindows, id.rawValue != 0 else { return nil }
        let windows = [NSNumber(value: id.rawValue)] as CFArray
        guard let values = copySpacesForWindows(connection, Self.allSpacesMask, windows)?.takeRetainedValue()
                as? [NSNumber] else { return nil }
        return values.map { SpaceID(rawValue: $0.uint64Value) }
    }
}
