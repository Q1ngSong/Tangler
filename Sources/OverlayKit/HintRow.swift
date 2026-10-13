import CoreKit
import Contracts

/// One line of the leader hint panel: the key to press and what it does.
public struct HintRow: Equatable, Identifiable, Sendable {
    /// As printed on the key cap.
    public var key: String
    public var title: String
    /// The key opens more keys instead of running a command.
    public var isGroup: Bool

    public var id: String { key }

    public init(key: String, title: String, isGroup: Bool) {
        self.key = key
        self.title = title
        self.isGroup = isGroup
    }

    /// Rows for the options `CommandRegistry.resolveLeader` offers. Commands come first in
    /// the registry's order, which follows the modules' declarations and so keeps related
    /// commands together; groups follow, so the keys that lead further sit at the bottom.
    /// A key offered twice keeps its first option.
    public static func rows(from options: [LeaderOption]) -> [HintRow] {
        var seen: Set<String> = []
        let unique = options.filter { seen.insert($0.keys).inserted }
        let ordered = unique.filter { !$0.isGroup } + unique.filter(\.isGroup)
        return ordered.map { HintRow(key: keyCap(for: $0.keys), title: $0.title, isGroup: $0.isGroup) }
    }

    /// Read by VoiceOver, e.g. "D：移到其他显示器，还有下一级".
    public var accessibilityLabel: String {
        isGroup ? L10n.text("overlaykit.more.keys.available", String(describing: (key)), String(describing: (title))) : L10n.text("text.labelValue", key, title)
    }

    /// The registry names an `.anyDigit` position "数字"; a key cap reads better as a range.
    static func keyCap(for label: String) -> String {
        label == KeyPattern.anyDigit.description ? "0–9" : label
    }
}
