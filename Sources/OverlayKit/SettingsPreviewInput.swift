import CoreKit
import Contracts
import SwiftUI

/// A preview names an operation; it never owns a copy of that operation's shortcut.
public enum SettingsPreviewInput: Equatable {
    case command(CommandID, argument: String? = nil)
    case drag(Modifiers)
    case gesture(symbol: String, label: String)
}

/// A semantic key demonstration, resolved against the same bindings as the visible keycaps.
public enum SettingsPreviewInputPlayback {
    case invocation(time: Double)
    case cycling(time: Double)
}

public struct SettingsInputBindings {
    public var trigger: LeaderTrigger
    public var commands: [CommandSpec]

    public init(trigger: LeaderTrigger = .holdRightCommand, commands: [CommandSpec] = []) {
        self.trigger = trigger
        self.commands = commands
    }

    enum Token: Equatable {
        case entry(String), key(String), next, symbol(String, String)

        var label: String {
            switch self {
            case .entry(let keys): L10n.text("overlaykit.leader", String(describing: (keys)))
            case .key(let key): key
            case .next: L10n.text("overlaykit.then")
            case .symbol(_, let label): label
            }
        }
    }

    func cyclesBackward(for input: SettingsPreviewInput) -> Bool {
        guard case .command(let id, _) = input else { return false }
        return commands.first { $0.id == id }?.globalShortcut?.modifiers.contains(.shift) == true
    }

    func pressedIndices(for input: SettingsPreviewInput, playback: SettingsPreviewInputPlayback) -> Set<Int> {
        let tokens = tokens(for: input)
        let keys = tokens.indices.filter { index in
            switch tokens[index] {
            case .entry, .key: true
            case .next, .symbol: false
            }
        }
        guard let last = keys.last else { return [] }
        let time: Double
        let cycling: Bool
        switch playback {
        case .invocation(let value): time = value; cycling = false
        case .cycling(let value): time = value; cycling = true
        }
        // Leader sequences press one cap at a time; chord modifiers remain held.
        if tokens.contains(.next) {
            let step = 1.4 / Double(keys.count)
            return Set(keys.enumerated().compactMap { offset, index in
                let start = 0.7 + Double(offset) * step
                return time >= start && time < start + step * 0.8 ? index : nil
            })
        }
        let release = cycling ? 3.45 : 2.1
        guard time >= 0.7 && time < release else { return [] }
        var pressed = Set(keys.dropLast())
        let keyDown = cycling ? ((0.95..<1.3).contains(time) || (2.05..<2.45).contains(time))
            : (1.4..<2.1).contains(time)
        if keyDown { pressed.insert(last) }
        return pressed
    }

    func tokens(for input: SettingsPreviewInput) -> [Token] {
        switch input {
        case .drag(let modifiers):
            return ShortcutKeySymbols.labels(modifiers).map(Token.key) + [.symbol("cursorarrow.motionlines", L10n.text("overlaykit.drag"))]
        case .gesture(let symbol, let label): return [.symbol(symbol, label)]
        case .command(let id, let argument):
            guard let spec = commands.first(where: { $0.id == id }) else {
                return [.symbol("keyboard", L10n.text("overlaykit.no.shortcut.assigned"))]
            }
            if let chord = spec.globalShortcut {
                return (ShortcutKeySymbols.labels(chord.modifiers) + [ShortcutKeySymbols.symbol(chord.key)]).map(Token.key)
            }
            guard let sequence = spec.leaderKeys.first, !sequence.patterns.isEmpty else {
                return [.symbol("keyboard", L10n.text("overlaykit.no.shortcut.assigned"))]
            }
            var result: [Token] = [.entry(ShortcutKeySymbols.label(trigger))]
            for pattern in sequence.patterns {
                result.append(.next)
                switch pattern {
                case .key(let key): result.append(.key(ShortcutKeySymbols.symbol(key)))
                case .anyDigit: result.append(.key(argument ?? L10n.text("contracts.digit")))
                }
            }
            return result
        }
    }
}

private struct SettingsInputBindingsKey: EnvironmentKey {
    static let defaultValue = SettingsInputBindings()
}

public extension EnvironmentValues {
    var settingsInputBindings: SettingsInputBindings {
        get { self[SettingsInputBindingsKey.self] }
        set { self[SettingsInputBindingsKey.self] = newValue }
    }
}

/// One compact legend for every preview; the Tangler mark stands for the configured entry key.
public struct SettingsPreviewInputHint: View {
    let input: SettingsPreviewInput
    let active: Bool
    let playback: SettingsPreviewInputPlayback?
    @Environment(\.settingsInputBindings) private var bindings

    public init(_ input: SettingsPreviewInput, active: Bool = false, playback: SettingsPreviewInputPlayback? = nil) {
        self.input = input
        self.active = active
        self.playback = playback
    }

    public var body: some View {
        let tokens = bindings.tokens(for: input)
        let pressed = playback.map { bindings.pressedIndices(for: input, playback: $0) }
        HStack(spacing: 4) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                if token == .next {
                    Image(systemName: "chevron.right").font(.system(size: 7, weight: .semibold)).foregroundStyle(.secondary)
                } else {
                    let down = pressed?.contains(index) ?? active
                    cap(token).frame(minWidth: 19, minHeight: 22)
                        .padding(.horizontal, 3)
                        .foregroundStyle(down ? Color.white : Color.primary)
                        .background(down ? Color.accentColor : .white.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(down ? 0.65 : 0.15), lineWidth: 0.7))
                        .scaleEffect(down ? 0.94 : 1)
                }
            }
        }
        .font(.system(size: 11, weight: .medium))
        .padding(5).settingsPreviewSurface(cornerRadius: 10)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor.opacity((pressed.map { !$0.isEmpty } ?? active) ? 0.7 : 0), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tokens.map(\.label).joined(separator: L10n.text("text.listSeparator")))
        .help(tokens.map(\.label).joined(separator: " "))
    }

    @ViewBuilder private func cap(_ token: SettingsInputBindings.Token) -> some View {
        switch token {
        case .entry: TanglerMark().frame(width: 16, height: 16)
        case .key(let key): Text(key)
        case .symbol(let symbol, _): Image(systemName: symbol).font(.system(size: 13))
        case .next: EmptyView()
        }
    }
}
