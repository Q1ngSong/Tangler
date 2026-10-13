import CoreKit
import CoreGraphics

/// A key by lowercase name: "a"..."z", "0"..."9", "left", "right", "up", "down",
/// "space", "escape", "return", "tab", "`" and the other names in `CoreKit.KeyCodes`.
/// Keys without a name (F-keys, keypad, Home/End) arrive as "#<virtual key code>".
public struct Key: RawRepresentable, Hashable, Codable, Sendable,
    ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue.lowercased() }
    public init(stringLiteral value: String) { self.init(rawValue: value) }

    public static let left: Key = "left"
    public static let right: Key = "right"
    public static let up: Key = "up"
    public static let down: Key = "down"
    public static let space: Key = "space"
    public static let escape: Key = "escape"
    public static let returnKey: Key = "return"
    public static let tab: Key = "tab"
    public static let backtick: Key = "`"

    public static func digit(_ value: Int) -> Key { Key(rawValue: String(value)) }

    /// 0...9 for digit keys, otherwise nil.
    public var digitValue: Int? { rawValue.count == 1 ? Int(rawValue) : nil }

    /// How the key appears in hints and in COMMANDS.md.
    public var symbol: String {
        switch rawValue {
        case "left": return "←"
        case "right": return "→"
        case "up": return "↑"
        case "down": return "↓"
        case "space": return L10n.text("contracts.space")
        case "escape": return "Esc"
        case "return": return L10n.text("contracts.return")
        case "tab": return "Tab"
        default: return rawValue.uppercased()
        }
    }

    public var description: String { symbol }
}

/// One position in a leader key sequence.
public enum KeyPattern: Hashable, Codable, Sendable, CustomStringConvertible {
    case key(Key)
    /// Any of 0...9; the digit reaches the command as `CommandContext.argument`.
    case anyDigit

    public func matches(_ key: Key) -> Bool {
        switch self {
        case .key(let expected): return expected == key
        case .anyDigit: return key.digitValue != nil
        }
    }

    public var description: String {
        switch self {
        case .key(let key): return key.symbol
        case .anyDigit: return L10n.text("contracts.digit")
        }
    }
}

/// Keys pressed one after another after the leader trigger, e.g. "D →".
public struct KeySequence: Hashable, Codable, Sendable, CustomStringConvertible {
    public var patterns: [KeyPattern]

    public init(_ patterns: [KeyPattern]) { self.patterns = patterns }
    public init(_ patterns: KeyPattern...) { self.patterns = patterns }
    public init(_ keys: Key...) { self.patterns = keys.map(KeyPattern.key) }

    public var description: String { patterns.map(\.description).joined(separator: " ") }
}

public struct Modifiers: OptionSet, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let control = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let shift = Modifiers(rawValue: 1 << 2)
    public static let command = Modifiers(rawValue: 1 << 3)
    public static let function = Modifiers(rawValue: 1 << 4)

    /// macOS order: ⌃⌥⇧⌘, then fn.
    public var description: String {
        var text = ""
        if contains(.control) { text += "⌃" }
        if contains(.option) { text += "⌥" }
        if contains(.shift) { text += "⇧" }
        if contains(.command) { text += "⌘" }
        if contains(.function) { text += "fn" }
        return text
    }
}

/// A key pressed with modifiers held, e.g. ⌘Tab.
public struct KeyChord: Hashable, Codable, Sendable, CustomStringConvertible {
    public var key: Key
    public var modifiers: Modifiers

    public init(_ key: Key, modifiers: Modifiers) {
        self.key = key
        self.modifiers = modifiers
    }

    public var description: String { modifiers.description + key.symbol }
}

public struct KeyPress: Hashable, Sendable {
    public var key: Key
    public var modifiers: Modifiers
    public var isRepeat: Bool

    public init(_ key: Key, modifiers: Modifiers = [], isRepeat: Bool = false) {
        self.key = key
        self.modifiers = modifiers
        self.isRepeat = isRepeat
    }
}

public enum MouseButton: String, Codable, Sendable {
    case left, right, other
}

public struct MouseEvent: Equatable, Sendable {
    public var location: CGPoint
    public var button: MouseButton
    public var modifiers: Modifiers

    public init(location: CGPoint, button: MouseButton = .left, modifiers: Modifiers = []) {
        self.location = location
        self.button = button
        self.modifiers = modifiers
    }
}

public struct ScrollEvent: Equatable, Sendable {
    public var location: CGPoint
    public var delta: CGVector
    /// True for trackpads and Magic Mouse, false for wheel notches.
    public var isContinuous: Bool

    public init(location: CGPoint, delta: CGVector, isContinuous: Bool) {
        self.location = location
        self.delta = delta
        self.isContinuous = isContinuous
    }
}

/// Global input. Consumers switch over every case without `default`.
public enum InputEvent: Equatable, Sendable {
    case leaderTriggered
    case shortcut(id: String)
    case mouseDown(MouseEvent)
    case mouseDragged(MouseEvent)
    case mouseUp(MouseEvent)
    case mouseMoved(CGPoint)
    case modifiersChanged(Modifiers)
    case scroll(ScrollEvent)
}

public struct InputEventFilter: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let leader = InputEventFilter(rawValue: 1 << 0)
    public static let shortcuts = InputEventFilter(rawValue: 1 << 1)
    public static let mouseButtons = InputEventFilter(rawValue: 1 << 2)
    /// High frequency; subscribe only while needed, e.g. during Dock hover.
    public static let mouseMoved = InputEventFilter(rawValue: 1 << 3)
    public static let modifiers = InputEventFilter(rawValue: 1 << 4)
    public static let scroll = InputEventFilter(rawValue: 1 << 5)
    public static let standard: InputEventFilter = [.leader, .shortcuts, .mouseButtons, .modifiers, .scroll]

    public func admits(_ event: InputEvent) -> Bool {
        switch event {
        case .leaderTriggered: return contains(.leader)
        case .shortcut: return contains(.shortcuts)
        case .mouseDown, .mouseDragged, .mouseUp: return contains(.mouseButtons)
        case .mouseMoved: return contains(.mouseMoved)
        case .modifiersChanged: return contains(.modifiers)
        case .scroll: return contains(.scroll)
        }
    }
}

public enum LeaderTrigger: Hashable, Codable, Sendable {
    /// Press and release the right Command key, however slowly, with no other key in between;
    /// leader mode then waits for keys.
    case tapRightCommand
    /// Hold the right Command key: leader mode starts as it goes down, keys pressed while it is
    /// held reach leader mode without ⌘, and right Command is no ordinary ⌘ meanwhile.
    case holdRightCommand
    case chord(KeyChord)
}
