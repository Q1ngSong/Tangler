import Contracts

/// The events that describe how a window changed between two snapshots. Every path that
/// learns something new about a window (scans, notifications, readbacks) reports through
/// this, so the same change is described the same way wherever it was noticed.
enum WindowDiff {
    static func events(from old: WindowInfo, to new: WindowInfo) -> [WindowEvent] {
        var events: [WindowEvent] = []
        if old.frame.origin != new.frame.origin { events.append(.moved(new.id, new.frame)) }
        if old.frame.size != new.frame.size { events.append(.resized(new.id, new.frame)) }
        if old.title != new.title { events.append(.titleChanged(new.id, new.title)) }
        if old.isMinimized != new.isMinimized { events.append(new.isMinimized ? .minimized(new.id) : .restored(new.id)) }
        return events
    }
}
