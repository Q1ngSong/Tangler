import Darwin

/// The private CoreGraphics calls that switch system hot keys on and off, resolved at
/// launch. macOS has no public way to turn off ⌘Tab; without these calls InputKit can
/// only swallow the keys it receives (design section 5.2).
struct SymbolicHotKeyFunctions {
    /// Returns true when the system accepted the change.
    var setEnabled: (_ hotKey: UInt32, _ enabled: Bool) -> Bool
    /// Nil when only the setter exists; callers then assume a hot key was on.
    var isEnabled: ((_ hotKey: UInt32) -> Bool)?

    /// Nil when the setter cannot be found. `lookup` resolves a symbol name.
    static func load(lookup: (String) -> UnsafeMutableRawPointer? = { dlsym(searchAllImages, $0) })
        -> SymbolicHotKeyFunctions? {
        typealias Setter = @convention(c) (UInt32, Bool) -> Int32
        typealias Getter = @convention(c) (UInt32) -> Bool
        guard let setterSymbol = lookup("CGSSetSymbolicHotKeyEnabled") else { return nil }
        let setter = unsafeBitCast(setterSymbol, to: Setter.self)
        let getter = lookup("CGSIsSymbolicHotKeyEnabled").map { unsafeBitCast($0, to: Getter.self) }
        // The launch probe's harmless call (design section 5.2): read ⌘Tab's state once.
        _ = getter?(1)
        return SymbolicHotKeyFunctions(
            setEnabled: { hotKey, enabled in setter(hotKey, enabled) == 0 },
            isEnabled: getter.map { getter in { hotKey in getter(hotKey) } })
    }

    /// RTLD_DEFAULT, which Swift does not import: search every loaded image, so the
    /// symbol is found wherever the system keeps it.
    private static let searchAllImages = UnsafeMutableRawPointer(bitPattern: -2)
}
