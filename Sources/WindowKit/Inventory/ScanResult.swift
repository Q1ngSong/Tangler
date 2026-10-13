import Contracts

/// A window read during a scan or after a notification. `stamp` orders reads: a larger
/// stamp was taken later, so it wins over anything older (see `ReadStamps`).
struct ScannedWindow<Handle: Hashable> {
    var info: WindowInfo
    var handle: Handle
    var stamp: UInt64
    /// The parts of `info` this read looked at; the others only repeat earlier knowledge.
    var fields: WindowFields = .all
}

struct ScanResult<Handle: Hashable> {
    /// Taken before anything was read. Windows learned after it are newer than the scan.
    var startStamp: UInt64
    /// Front to back.
    var windows: [ScannedWindow<Handle>]
    /// Applications whose window list was read. The others timed out or were not part of the scan.
    var scannedPIDs: Set<Int32>
    /// Every manageable application at the time, for full scans; nil when only some were scanned.
    var runningPIDs: Set<Int32>?
    /// Every window the window server still has; nil when that list could not be read.
    var liveWindowIDs: Set<WindowID>?
    /// Known windows of scanned applications that the window server still has but that are
    /// closed: some apps only order a window out on close and keep it for later.
    var closedIDs: Set<WindowID> = []

    var isFull: Bool { runningPIDs != nil }
}
