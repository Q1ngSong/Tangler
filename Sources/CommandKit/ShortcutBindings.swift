import CoreKit
import Contracts

/// The chords the registry holds in InputService, one per command, under the command ID.
struct ShortcutBindings {
    private(set) var bound: [CommandID: KeyChord] = [:]

    /// Makes InputService hold exactly the commands' chords. Changed chords are released
    /// before new ones are claimed, so two commands can swap chords. Returns each chord
    /// InputService refused, with the reason.
    mutating func update(to commands: [CommandSpec], input: any InputService) -> [KeyChord: String] {
        let wanted = Dictionary(uniqueKeysWithValues: commands.compactMap { spec in
            spec.globalShortcut.map { (spec.id, $0) }
        })
        for (id, chord) in bound where wanted[id] != chord {
            input.unregisterShortcut(id: id.rawValue)
            bound[id] = nil
        }
        var refused: [KeyChord: String] = [:]
        for spec in commands {
            guard let chord = spec.globalShortcut, bound[spec.id] == nil else { continue }
            do {
                try input.registerShortcut(chord, id: spec.id.rawValue)
                bound[spec.id] = chord
            } catch InputError.shortcutInUse(let owner) {
                refused[chord] = L10n.text("commandkit.already.used.by", String(describing: (owner)))
            } catch {
                refused[chord] = L10n.text("commandkit.could.not.register", String(describing: (error)))
            }
        }
        return refused
    }
}
