import Contracts

/// Global shortcuts by id. Modifiers must match exactly, except that fn never counts.
struct ShortcutTable {
    private var chordsByID: [String: KeyChord] = [:]
    private var idsByChord: [KeyChord: String] = [:]

    /// Throws `InputError.shortcutInUse` naming the current owner when another id has the chord.
    /// Registering an id again moves it to the new chord.
    mutating func register(_ chord: KeyChord, id: String) throws {
        let chord = KeyChord(chord.key, modifiers: chord.modifiers.ignoringFunction)
        if let owner = idsByChord[chord], owner != id {
            throw InputError.shortcutInUse(id: owner)
        }
        unregister(id: id)
        chordsByID[id] = chord
        idsByChord[chord] = id
    }

    mutating func unregister(id: String) {
        guard let chord = chordsByID.removeValue(forKey: id) else { return }
        idsByChord[chord] = nil
    }

    func owner(of key: Key, modifiers: Modifiers) -> String? {
        idsByChord[KeyChord(key, modifiers: modifiers.ignoringFunction)]
    }
}
