import Contracts

/// Parts of a window's description that are read, and therefore stamped, separately: a frame
/// readback reads only the frame and a Space move only the Spaces, so an older read can still
/// bring news about the parts a newer one did not read.
struct WindowFields: OptionSet, Hashable {
    let rawValue: Int

    /// The frame and the display it is on.
    static let frame = WindowFields(rawValue: 1 << 0)
    static let spaces = WindowFields(rawValue: 1 << 1)
    /// Everything else: title, minimized, fullscreen, document and application.
    static let details = WindowFields(rawValue: 1 << 2)
    static let all: WindowFields = [.frame, .spaces, .details]
}

/// When each part of a window was last read (see `ReadStamps`).
struct FieldStamps: Equatable {
    private var frame: UInt64
    private var spaces: UInt64
    private var details: UInt64

    /// `fields` read at `stamp`; the other parts count as never read.
    init(_ fields: WindowFields = .all, at stamp: UInt64) {
        frame = fields.contains(.frame) ? stamp : 0
        spaces = fields.contains(.spaces) ? stamp : 0
        details = fields.contains(.details) ? stamp : 0
    }

    /// The newest read of any part.
    var newest: UInt64 { max(frame, spaces, details) }

    /// The parts of `fields` last read before `stamp`.
    func older(_ fields: WindowFields, than stamp: UInt64) -> WindowFields {
        var older: WindowFields = []
        if fields.contains(.frame) && frame < stamp { older.insert(.frame) }
        if fields.contains(.spaces) && spaces < stamp { older.insert(.spaces) }
        if fields.contains(.details) && details < stamp { older.insert(.details) }
        return older
    }

    mutating func set(_ fields: WindowFields, to stamp: UInt64) {
        if fields.contains(.frame) { frame = stamp }
        if fields.contains(.spaces) { spaces = stamp }
        if fields.contains(.details) { details = stamp }
    }
}

extension WindowInfo {
    /// Takes the parts named by `fields` from `other`, which describes the same window.
    mutating func take(_ fields: WindowFields, from other: WindowInfo) {
        if fields.contains(.frame) {
            frame = other.frame
            displayID = other.displayID
        }
        if fields.contains(.spaces) { spaceIDs = other.spaceIDs }
        if fields.contains(.details) {
            pid = other.pid
            bundleID = other.bundleID
            appName = other.appName
            title = other.title
            isMinimized = other.isMinimized
            isFullscreen = other.isFullscreen
            documentURL = other.documentURL
        }
    }
}
