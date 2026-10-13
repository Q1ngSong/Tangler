import Foundation

/// Where the states found before suppression wait until they are restored. If Tangler is
/// killed while the hot keys are off, the next launch finds them here and puts them back;
/// without this it would take "off" for the original state and keep ⌘Tab off for good.
struct HotKeyStateStore: @unchecked Sendable {
    var load: () -> [UInt32: Bool]?
    var save: ([UInt32: Bool]?) -> Void

    static let defaultsKey = "tangler.input.switcherHotKeysBeforeSuppression"

    static let userDefaults = HotKeyStateStore(
        load: {
            guard let saved = UserDefaults.standard.dictionary(forKey: HotKeyStateStore.defaultsKey) as? [String: Bool]
            else { return nil }
            return Dictionary(uniqueKeysWithValues: saved.compactMap { key, value in UInt32(key).map { ($0, value) } })
        },
        save: { states in
            if let states {
                let stored = Dictionary(uniqueKeysWithValues: states.map { (String($0.key), $0.value) })
                UserDefaults.standard.set(stored, forKey: HotKeyStateStore.defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: HotKeyStateStore.defaultsKey)
            }
        })

    /// Keeps nothing; for tests that do not care about relaunches.
    static let none = HotKeyStateStore(load: { nil }, save: { _ in })
}

/// The system's ⌘Tab, ⇧⌘Tab and ⌘` hot keys. Turns them off for the switcher module and
/// later back to exactly the states found before, so a hot key someone else had turned
/// off stays off.
final class SwitcherHotKeys: @unchecked Sendable {
    /// Symbolic hot key numbers for ⌘Tab, ⇧⌘Tab and ⌘` (the key above Tab).
    static let hotKeys: [UInt32] = [1, 2, 6]

    private let functions: SymbolicHotKeyFunctions?
    private let lock = NSLock()
    /// The states before the first change; empty while nothing is changed.
    private var originalStates: [UInt32: Bool] = [:]

    private let store: HotKeyStateStore

    init(functions: SymbolicHotKeyFunctions?, store: HotKeyStateStore = .none) {
        self.functions = functions
        self.store = store
        restoreStatesLeftByAnEarlierRun()
    }

    /// An earlier run that was killed while the hot keys were off left their states behind.
    private func restoreStatesLeftByAnEarlierRun() {
        guard let functions, let saved = store.load() else { return }
        for (hotKey, state) in saved { _ = functions.setEnabled(hotKey, state) }
        store.save(nil)
    }

    var isAvailable: Bool { functions != nil }
    var isSuppressed: Bool { lock.withLock { !originalStates.isEmpty } }

    /// False when the private calls are missing or the system refused a change.
    func setSuppressed(_ suppressed: Bool) -> Bool {
        guard let functions else { return false }
        return lock.withLock {
            var accepted = true
            if suppressed {
                for hotKey in Self.hotKeys {
                    if originalStates[hotKey] == nil {
                        originalStates[hotKey] = functions.isEnabled?(hotKey) ?? true
                    }
                    accepted = functions.setEnabled(hotKey, false) && accepted
                }
                store.save(originalStates)
            } else {
                for (hotKey, state) in originalStates {
                    accepted = functions.setEnabled(hotKey, state) && accepted
                }
                originalStates.removeAll()
                store.save(nil)
            }
            return accepted
        }
    }

    /// Puts back whatever was changed. Called when the service stops or the app quits.
    func restore() {
        if isSuppressed { _ = setSuppressed(false) }
    }
}
