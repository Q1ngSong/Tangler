import Contracts
import CoreGraphics
import Foundation

/// The latest thumbnail of each window, reused for `lifetime` when the same size limit is
/// asked for again. Keeps at most `capacity` windows and drops the least recently used first.
final class ThumbnailCache: @unchecked Sendable {
    typealias Instant = ContinuousClock.Instant

    private struct Entry {
        var image: CGImage
        var maxPixelSize: Int
        var capturedAt: Instant
        var lastUse: UInt64
    }

    let capacity: Int
    let lifetime: Duration
    private let lock = NSLock()
    private var entries: [WindowID: Entry] = [:]
    private var uses: UInt64 = 0

    init(capacity: Int = 64, lifetime: Duration = .seconds(2)) {
        self.capacity = max(1, capacity)
        self.lifetime = lifetime
    }

    var count: Int { lock.withLock { entries.count } }

    func image(for id: WindowID, maxPixelSize: Int, now: Instant) -> CGImage? {
        lock.withLock {
            guard var entry = entries[id] else { return nil }
            guard isFresh(entry, now: now) else {
                entries[id] = nil
                return nil
            }
            guard entry.maxPixelSize == maxPixelSize else { return nil }
            entry.lastUse = nextUse()
            entries[id] = entry
            return entry.image
        }
    }

    func insert(_ image: CGImage, for id: WindowID, maxPixelSize: Int, now: Instant) {
        lock.withLock {
            dropExpired(now: now)
            entries[id] = Entry(image: image, maxPixelSize: maxPixelSize, capturedAt: now, lastUse: nextUse())
            if entries.count > capacity, let oldest = entries.min(by: { $0.value.lastUse < $1.value.lastUse }) {
                entries[oldest.key] = nil
            }
        }
    }

    /// Drops thumbnails too old to reuse and returns how many are left.
    @discardableResult
    func removeExpired(now: Instant) -> Int {
        lock.withLock {
            dropExpired(now: now)
            return entries.count
        }
    }

    private func dropExpired(now: Instant) {
        entries = entries.filter { isFresh($0.value, now: now) }
    }

    private func isFresh(_ entry: Entry, now: Instant) -> Bool {
        now - entry.capturedAt < lifetime
    }

    private func nextUse() -> UInt64 {
        uses += 1
        return uses
    }
}
