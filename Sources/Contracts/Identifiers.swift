import Foundation

/// System window number (`CGWindowID`), stable for the lifetime of a window.
public struct WindowID: RawRepresentable, Hashable, Comparable, Codable, Sendable,
    ExpressibleByIntegerLiteral, CustomStringConvertible {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public init(integerLiteral value: UInt32) { rawValue = value }
    public var description: String { "window \(rawValue)" }
    public static func < (lhs: WindowID, rhs: WindowID) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Display UUID string; stays the same when a display is unplugged and reconnected.
public struct DisplayID: RawRepresentable, Hashable, Codable, Sendable,
    ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public var description: String { rawValue }
}

/// Mission Control desktop (Space) identifier.
public struct SpaceID: RawRepresentable, Hashable, Codable, Sendable,
    ExpressibleByIntegerLiteral, CustomStringConvertible {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }
    public init(integerLiteral value: UInt64) { rawValue = value }
    public var description: String { "space \(rawValue)" }
}

/// Identifies a feature module, e.g. "layout". Command IDs start with it.
public struct ModuleID: RawRepresentable, Hashable, Codable, Sendable,
    ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public var description: String { rawValue }
}

/// "module.action", e.g. "layout.leftHalf".
public struct CommandID: RawRepresentable, Hashable, Comparable, Codable, Sendable,
    ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public var description: String { rawValue }
    /// The part before the first dot, which must equal the declaring module's ID.
    public var modulePrefix: String { String(rawValue.prefix { $0 != "." }) }
    public static func < (lhs: CommandID, rhs: CommandID) -> Bool { lhs.rawValue < rhs.rawValue }
}
