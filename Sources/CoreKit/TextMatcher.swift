import Foundation

/// Case-, accent- and pinyin-insensitive matching for search fields (design section 4.2).
public enum TextMatcher {
    /// How a query matched; earlier cases rank higher.
    public enum Match: Int, Comparable, Sendable {
        case prefix, contains, pinyin, initials

        public static func < (lhs: Match, rhs: Match) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// How `query` matches `text`, or nil. An empty query matches everything as `.prefix`.
    public static func match(_ query: String, in text: String) -> Match? {
        let needle = fold(query).replacingOccurrences(of: " ", with: "")
        guard !needle.isEmpty else { return .prefix }
        let compact = fold(text).replacingOccurrences(of: " ", with: "")
        if compact.hasPrefix(needle) { return .prefix }
        if compact.contains(needle) { return .contains }
        let syllables = latinSyllables(of: text)
        if syllables.joined().contains(needle) { return .pinyin }
        if String(syllables.compactMap(\.first)).contains(needle) { return .initials }
        return nil
    }

    /// First letters of each pinyin syllable or Latin word: "左半屏" → "zbp".
    public static func initials(of text: String) -> String {
        String(latinSyllables(of: text).compactMap(\.first))
    }

    static func latinSyllables(of text: String) -> [String] {
        let latin = text.applyingTransform(.toLatin, reverse: false) ?? text
        return fold(latin).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil).lowercased()
    }
}
