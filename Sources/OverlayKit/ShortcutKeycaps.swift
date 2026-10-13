import CoreKit
import Contracts
import SwiftUI

/// Settings use macOS key glyphs without changing persisted key names or command documentation.
public enum ShortcutKeySymbols {
    public static func symbol(_ key: Key) -> String {
        switch key.rawValue {
        case "tab": "⇥"
        case "return": "↩"
        case "escape": "⎋"
        case "space": "␣"
        case "delete": "⌫"
        default: key.symbol
        }
    }

    public static func label(_ chord: KeyChord) -> String {
        (labels(chord.modifiers) + [symbol(chord.key)]).joined(separator: " ")
    }

    public static func labels(_ value: Modifiers) -> [String] {
        let modifiers: [(Modifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"), (.function, "fn")]
        return modifiers.filter { value.contains($0.0) }.map(\.1)
    }

    public static func label(_ trigger: LeaderTrigger) -> String {
        switch trigger {
        case .holdRightCommand, .tapRightCommand: L10n.text("overlaykit.right")
        case .chord(let chord): label(chord)
        }
    }

    /// Include the entry key so a single command column still describes the whole gesture.
    public static func label(_ sequences: [KeySequence], trigger: LeaderTrigger) -> String {
        guard !sequences.isEmpty else { return "—" }
        return sequences.map { sequence in
            ([label(trigger)] + sequence.patterns.map { pattern in
                switch pattern {
                case .key(let key): symbol(key)
                case .anyDigit: L10n.text("contracts.digit")
                }
            }).joined(separator: " › ")
        }.joined(separator: "\n")
    }
}

/// Separate keycaps and chevrons distinguish a leader sequence from a simultaneous chord.
public struct ShortcutSequenceKeycaps: View {
    private let sequences: [KeySequence]

    public init(_ sequences: [KeySequence]) { self.sequences = sequences }

    public var body: some View {
        VStack(spacing: 5) {
            if sequences.isEmpty { Text("—").foregroundStyle(.tertiary) }
            ForEach(Array(sequences.enumerated()), id: \.offset) { _, sequence in
                HStack(spacing: 4) {
                    ForEach(Array(sequence.patterns.enumerated()), id: \.offset) { index, pattern in
                        if index > 0 { Image(systemName: "chevron.right").font(.system(size: 7)).foregroundStyle(.tertiary) }
                        switch pattern {
                        case .key(let key): KeyCap(ShortcutKeySymbols.symbol(key), size: .small)
                        case .anyDigit: KeyCap(L10n.text("contracts.digit"), size: .small)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sequences.isEmpty ? L10n.text("overlaykit.no.leader.sequence") : sequences.map(\.description).joined(separator: L10n.text("overlaykit.or")))
    }
}
