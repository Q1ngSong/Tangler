import CoreKit
import Contracts

/// Applies the user's key overrides to the declared commands. Declared keys never clash with
/// each other (registration makes sure of that), so every clash involves an override, and an
/// override gives way: to a declared key first; between two overrides, the later command's does.
enum KeyOverrides {
    struct Result {
        var commands: [CommandSpec]
        var problems: [OverrideProblem] = []
        /// Commands left without their declared chord because another InputService client holds it.
        var declaredChordsTaken: [CommandID: String] = [:]
    }

    /// `takenChords`: chords another InputService client holds, with the reason. No command
    /// comes back with one of them.
    static func apply(_ settings: CommandKeySettings, to declared: [CommandSpec],
                      takenChords: [KeyChord: String] = [:]) -> Result {
        var result = Result(commands: declared)
        applyLeaderKeys(settings.leaderKeys, declared: declared, to: &result)
        applyShortcuts(settings.globalShortcuts, declared: declared, taken: takenChords, to: &result)
        return result
    }

    private static func applyLeaderKeys(_ overrides: [String: [KeySequence]], declared: [CommandSpec],
                                        to result: inout Result) {
        var overridden: Set<Int> = []
        for (index, spec) in declared.enumerated() {
            guard let keys = overrides[spec.id.rawValue], keys != spec.leaderKeys else { continue }
            if let reason = leaderKeysProblem(keys, for: spec) {
                result.problems.append(OverrideProblem(command: spec.id, field: .leaderKeys, reason: reason))
            } else {
                result.commands[index].leaderKeys = keys
                overridden.insert(index)
            }
        }
        while true {
            let commands = result.commands
            guard let clash = firstClash(among: commands.count, overridden: overridden, reasons: { i, j in
                leaderClash(commands[i], commands[j])
            }) else { return }
            result.commands[clash.loser].leaderKeys = declared[clash.loser].leaderKeys
            overridden.remove(clash.loser)
            result.problems.append(OverrideProblem(command: declared[clash.loser].id, field: .leaderKeys, reason: clash.reason))
        }
    }

    private static func applyShortcuts(_ overrides: [String: KeyChord?], declared: [CommandSpec],
                                       taken: [KeyChord: String], to result: inout Result) {
        var overridden: Set<Int> = []
        for (index, spec) in declared.enumerated() {
            guard let choice = overrides[spec.id.rawValue], choice != spec.globalShortcut else { continue }
            if let chord = choice, chord.modifiers.isDisjoint(with: [.control, .option, .command]) {
                result.problems.append(OverrideProblem(command: spec.id, field: .globalShortcut,
                                                       reason: L10n.text("commandkit.needs.or.to.avoid.interfering.with.typing", String(describing: (chord)))))
            } else {
                result.commands[index].globalShortcut = choice
                overridden.insert(index)
            }
        }
        // Each round reverts an override or unbinds a declared chord, so the loop ends.
        while true {
            let commands = result.commands
            if let hit = takenChord(in: commands, taken: taken) {
                let id = declared[hit.index].id
                if overridden.remove(hit.index) != nil {
                    result.commands[hit.index].globalShortcut = declared[hit.index].globalShortcut
                } else {
                    result.commands[hit.index].globalShortcut = nil
                    result.declaredChordsTaken[id] = hit.reason
                }
                result.problems.append(OverrideProblem(command: id, field: .globalShortcut, reason: "\(hit.chord) \(hit.reason)"))
            } else if let clash = firstClash(among: commands.count, overridden: overridden, reasons: { i, j in
                shortcutClash(commands[i], commands[j])
            }) {
                result.commands[clash.loser].globalShortcut = declared[clash.loser].globalShortcut
                overridden.remove(clash.loser)
                result.problems.append(OverrideProblem(command: declared[clash.loser].id, field: .globalShortcut, reason: clash.reason))
            } else {
                return
            }
        }
    }

    private static func takenChord(in commands: [CommandSpec], taken: [KeyChord: String])
        -> (index: Int, chord: KeyChord, reason: String)? {
        for (index, spec) in commands.enumerated() {
            if let chord = spec.globalShortcut, let reason = taken[chord] { return (index, chord, reason) }
        }
        return nil
    }

    private static func leaderKeysProblem(_ keys: [KeySequence], for spec: CommandSpec) -> String? {
        if !keys.isEmpty && !spec.entryPoints.contains(.leader) { return L10n.text("commandkit.this.command.cannot.use.a.leader.sequence") }
        if keys.contains(where: { $0.patterns.isEmpty }) { return L10n.text("commandkit.a.key.sequence.cannot.be.empty") }
        if keys.contains(where: { $0.patterns.contains(.key(.escape)) }) { return L10n.text("commandkit.esc.is.reserved.for.leaving.leader.mode") }
        for i in keys.indices {
            for j in keys.indices where j > i && CommandCatalog.overlaps(keys[i], keys[j]) {
                return L10n.text("commandkit.and.conflict", String(describing: (keys[i])), String(describing: (keys[j])))
            }
        }
        return nil
    }

    /// Why each command would give way to the other, or nil when their leader keys do not clash.
    private static func leaderClash(_ a: CommandSpec, _ b: CommandSpec) -> (String, String)? {
        for keys in a.leaderKeys {
            if let other = b.leaderKeys.first(where: { CommandCatalog.overlaps(keys, $0) }) {
                return (L10n.text("commandkit.conflicts.with", String(describing: (keys)), String(describing: (b.title)), String(describing: (other))), L10n.text("commandkit.conflicts.with", String(describing: (other)), String(describing: (a.title)), String(describing: (keys))))
            }
        }
        return nil
    }

    private static func shortcutClash(_ a: CommandSpec, _ b: CommandSpec) -> (String, String)? {
        guard let chord = a.globalShortcut, chord == b.globalShortcut else { return nil }
        return (L10n.text("commandkit.is.already.used.by", String(describing: (chord)), String(describing: (b.title))), L10n.text("commandkit.is.already.used.by", String(describing: (chord)), String(describing: (a.title))))
    }

    /// The clash to settle next and whose override gives way, with the reason.
    private static func firstClash(among count: Int, overridden: Set<Int>,
                                   reasons: (Int, Int) -> (String, String)?) -> (loser: Int, reason: String)? {
        var betweenOverrides: (loser: Int, reason: String)?
        for i in 0..<count {
            for j in (i + 1)..<count where overridden.contains(i) || overridden.contains(j) {
                guard let (first, second) = reasons(i, j) else { continue }
                switch (overridden.contains(i), overridden.contains(j)) {
                case (true, true): betweenOverrides = betweenOverrides ?? (j, second)
                case (true, false): return (i, first)
                case (false, _): return (j, second)
                }
            }
        }
        return betweenOverrides
    }
}
