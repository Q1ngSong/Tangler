import Contracts
import Foundation

/// A tab group of a checkpoint.
struct SavedTabGroup: Codable, Equatable, Sendable {
    /// Entries, in tab order.
    var members: [UUID]
    /// The entry whose tab is in front.
    var active: UUID
    /// The whole group, bar included, relative to the display's visible frame.
    var unitArea: UnitRect
}

/// The desktop a workspace owns. `uuid` is the system's name for it and survives while the
/// desktop exists.
struct BoundDesktop: Codable, Equatable, Sendable {
    var uuid: String
    var displayID: DisplayID
}
