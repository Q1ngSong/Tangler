import Contracts
import CoreKit
import Foundation

/// Finds and orders palette rows (design section 4.2): better matches first, then the most
/// recently used, so an empty query lists what was used last.
enum PaletteSearch {
    struct Candidates {
        var windows: [WindowInfo] = []
        /// Registered commands; only those offered in the palette are listed.
        var commands: [CommandSpec] = []
        var dynamicCommands: [DynamicCommand] = []
    }

    /// `target` is the window the palette acts on. It goes last among equal matches: switching
    /// to it would change nothing, so an empty query puts the previous window on top.
    @MainActor
    static func results(for query: String, in candidates: Candidates, recency: RecencyLog,
                        target: WindowID?) -> [PaletteItem] {
        var found: [(item: PaletteItem, match: TextMatcher.Match)] = []
        var seen: Set<PaletteItemID> = []
        // Rows are identified by ID, so a window listed twice must not appear twice.
        func add(_ kind: PaletteItem.Kind, _ match: TextMatcher.Match?) {
            let item = PaletteItem(kind: kind)
            if let match, seen.insert(item.id).inserted { found.append((item, match)) }
        }
        for window in candidates.windows {
            add(.window(window), best(query, in: [window.title, window.appName, "\(window.appName) \(window.title)"]))
        }
        let numbered = splitNumber(query)
        for spec in candidates.commands where spec.entryPoints.contains(.palette) {
            let names = [spec.title] + spec.searchAliases
            if let numbered, PaletteItem.takesNumber(spec), let match = best(numbered.rest, in: names) {
                add(.command(spec, argument: numbered.number), match)
            } else {
                add(.command(spec, argument: nil), best(query, in: names))
            }
        }
        for command in candidates.dynamicCommands {
            add(.dynamic(command), best(query, in: [command.title] + command.aliases))
        }
        let targetID = target.map(PaletteItemID.window)
        // Ties keep the order above: windows, then commands in registry order.
        let order = Dictionary(uniqueKeysWithValues: found.enumerated().map { ($1.item.id, $0) })
        return found.sorted { a, b in
            if a.match != b.match { return a.match < b.match }
            let (aIsTarget, bIsTarget) = (a.item.id == targetID, b.item.id == targetID)
            if aIsTarget != bIsTarget { return bIsTarget }
            let (aStamp, bStamp) = (recency.stamp(of: a.item.id) ?? 0, recency.stamp(of: b.item.id) ?? 0)
            if aStamp != bStamp { return aStamp > bStamp }
            return order[a.item.id, default: 0] < order[b.item.id, default: 0]
        }.map(\.item)
    }

    /// "桌面 3" → ("桌面", 3): a number after the name picks which one for a command that takes
    /// a digit, e.g. 移到第 N 个桌面. A number alone stays plain text to search for.
    static func splitNumber(_ query: String) -> (rest: String, number: Int)? {
        let text = query.folding(options: .widthInsensitive, locale: nil).trimmingCharacters(in: .whitespaces)
        let digits = String(text.reversed().prefix { $0.isASCII && $0.isNumber }.reversed())
        guard (1...3).contains(digits.count), let number = Int(digits) else { return nil }
        let rest = String(text.dropLast(digits.count)).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : (rest, number)
    }

    private static func best(_ query: String, in texts: [String]) -> TextMatcher.Match? {
        texts.compactMap { TextMatcher.match(query, in: $0) }.min()
    }
}
