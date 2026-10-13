import Contracts
import Foundation

/// Pairs saved windows with open ones. Every rule needs exactly one candidate and exactly one
/// saved window it could stand for; anything ambiguous stays unmatched rather than moving the
/// wrong window.
enum WindowMatcher {
    /// Saved window index → open window. `reserved` pairs are kept as they are and neither side
    /// takes part again. Without `allowsSoleRemainder`, a window is never matched just for being
    /// the only one its application has left, e.g. while a launched app is still opening windows.
    /// Without `contentsMustAgree`, as when a checkpoint is saved over, an entry that names
    /// contents is also paired by its title whatever the window shows now, and with the last
    /// window its application has left.
    static func match(_ saved: [SavedWindow], with open: [WindowIdentity], reserved: [Int: WindowID] = [:],
                      allowsSoleRemainder: Bool = true, contentsMustAgree: Bool = true) -> [Int: WindowID] {
        var result = reserved
        var used = Set(reserved.values)
        let pending = saved.indices.filter { reserved[$0] == nil }

        func unmatched(_ index: Int) -> Bool { result[index] == nil }
        func free(_ candidate: WindowIdentity) -> Bool { !used.contains(candidate.windowID) }
        func take(_ index: Int, _ candidates: [WindowIdentity], copies: Int) {
            guard copies == 1, candidates.count == 1, let candidate = candidates.first else { return }
            result[index] = candidate.windowID
            used.insert(candidate.windowID)
        }

        // The same window, still open: its number and process are unchanged.
        for index in pending {
            let item = saved[index]
            guard let ref = item.lastWindow else { continue }
            let copies = pending.filter { saved[$0].lastWindow == ref }.count
            take(index, open.filter {
                free($0) && $0.windowID == ref.windowID && $0.pid == ref.pid && $0.bundleID == item.bundleID
            }, copies: copies)
        }
        // The same document in the same application.
        for index in pending where unmatched(index) {
            let item = saved[index]
            guard let bundle = item.bundleID.nonEmpty, let document = item.documentIdentity else { continue }
            let copies = pending.filter { saved[$0].bundleID == bundle && saved[$0].documentIdentity == document }.count
            take(index, open.filter { free($0) && $0.bundleID == bundle && $0.documentURL == document }, copies: copies)
        }
        // The same title, and the same document when one is known and contents must agree.
        for index in pending where unmatched(index) {
            let item = saved[index]
            guard let bundle = item.bundleID.nonEmpty else { continue }
            let copies = pending.filter { saved[$0].bundleID == bundle && saved[$0].title == item.title }.count
            take(index, open.filter { candidate in
                guard free(candidate), candidate.bundleID == bundle, candidate.title == item.title else { return false }
                guard contentsMustAgree else { return true }
                return item.documentIdentity.map { $0 == candidate.documentURL } ?? true
            }, copies: copies)
        }
        guard allowsSoleRemainder else { return result }
        // The one window an application has left, unless the saved one names contents.
        for bundle in Set(pending.compactMap { saved[$0].bundleID.nonEmpty }).sorted() {
            let remaining = pending.filter { saved[$0].bundleID == bundle && unmatched($0) }
            guard remaining.count == 1, let index = remaining.first,
                  !contentsMustAgree || saved[index].contents.isEmpty else { continue }
            take(index, open.filter { free($0) && $0.bundleID == bundle }, copies: 1)
        }
        return result
    }
}

extension Optional where Wrapped == String {
    /// The string unless it is nil or empty.
    var nonEmpty: String? {
        guard let self, !self.isEmpty else { return nil }
        return self
    }
}
