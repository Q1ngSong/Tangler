/// macOS virtual key codes (ANSI layout) and the key names `Contracts.Key` uses.
/// InputKit (CGEvent) and OverlayKit (NSEvent) report the same codes, so both use this table.
public enum KeyCodes {
    public static let rightCommand: UInt16 = 0x36
    public static let leftCommand: UInt16 = 0x37

    public static func name(for keyCode: UInt16) -> String? { names[keyCode] }
    public static func keyCode(for name: String) -> UInt16? { codes[name] }

    static let names: [UInt16: String] = [
        0x00: "a", 0x01: "s", 0x02: "d", 0x03: "f", 0x04: "h", 0x05: "g", 0x06: "z", 0x07: "x",
        0x08: "c", 0x09: "v", 0x0B: "b", 0x0C: "q", 0x0D: "w", 0x0E: "e", 0x0F: "r", 0x10: "y",
        0x11: "t", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=",
        0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]", 0x1F: "o", 0x20: "u",
        0x21: "[", 0x22: "i", 0x23: "p", 0x24: "return", 0x25: "l", 0x26: "j", 0x27: "'", 0x28: "k",
        0x29: ";", 0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "n", 0x2E: "m", 0x2F: ".", 0x30: "tab",
        0x31: "space", 0x32: "`", 0x33: "delete", 0x35: "escape",
        0x7B: "left", 0x7C: "right", 0x7D: "down", 0x7E: "up",
    ]

    static let codes: [String: UInt16] = Dictionary(uniqueKeysWithValues: names.map { ($0.value, $0.key) })
}
