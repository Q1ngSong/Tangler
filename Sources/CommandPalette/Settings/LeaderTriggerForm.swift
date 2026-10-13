import Contracts

/// The leader trigger as the settings page edits it: right Command, held or tapped, or a chord,
/// with the switch and the recorded chord kept while the other choice is on.
struct LeaderTriggerForm: Equatable {
    enum Choice: Hashable {
        case rightCommand, chord
    }

    var choice: Choice
    /// With right Command: keys pressed while it is held run commands; off, it is pressed and
    /// let go first.
    var holds: Bool
    var chord: KeyChord?

    init(choice: Choice, holds: Bool = true, chord: KeyChord?) {
        self.choice = choice
        self.holds = holds
        self.chord = chord
    }

    init(_ trigger: LeaderTrigger) {
        switch trigger {
        case .holdRightCommand: self.init(choice: .rightCommand, holds: true, chord: nil)
        case .tapRightCommand: self.init(choice: .rightCommand, holds: false, chord: nil)
        case .chord(let chord): self.init(choice: .chord, holds: true, chord: chord)
        }
    }

    /// What to save. Leader mode is the way into every command, so choosing a chord keeps
    /// right Command until one is recorded.
    var trigger: LeaderTrigger {
        guard choice == .chord, let chord else { return holds ? .holdRightCommand : .tapRightCommand }
        return .chord(chord)
    }

    /// A command whose global shortcut is the chosen chord: the leader would take it over.
    func clash(in commands: [CommandSpec]) -> CommandSpec? {
        guard case .chord(let chord) = trigger else { return nil }
        return commands.first { $0.globalShortcut == chord }
    }
}
