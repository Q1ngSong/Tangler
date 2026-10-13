import Contracts

/// What leader mode does with each key (design section 4.2). Pure state: `LeaderMode` feeds it
/// key presses and command results and carries out the steps it returns.
struct LeaderSession {
    /// A command to run and what its handler receives.
    struct Run: Equatable {
        var command: CommandID
        var argument: Int?
        /// 0, then 1, 2, … while the same command is pressed again during the linger period.
        var repeatIndex: Int
        var lingers: Bool
    }

    enum Step: Equatable {
        /// The keys so far lead further; these are the next keys.
        case options([LeaderOption])
        case run(Run)
        /// Nothing continues with this key; the keys typed so far stay.
        case noMatch(KeyPress)
        case exit
        /// A held key repeating; leader mode reacts to separate presses only.
        case ignore
    }

    enum Outcome: Equatable {
        case linger
        case exit
    }

    /// Keys typed towards the next command.
    private(set) var typed: [Key] = []
    /// The last command, when it lingered; pressing it again counts its repeats.
    private(set) var lingering: Run?

    /// Once a command lingered, leader mode ends when no key comes for the linger period, so
    /// text typed right after a layout command is not swallowed for long.
    var timesOut: Bool { lingering != nil }
    /// Waiting at the top right after a lingering command: the hints fade.
    var isFaded: Bool { lingering != nil && typed.isEmpty }

    mutating func press(_ press: KeyPress, resolve: ([Key]) -> LeaderResolution,
                        lingers: (CommandID) -> Bool) -> Step {
        if press.isRepeat { return .ignore }
        if press.key == .escape { return .exit }
        // ⌘C and the like are shortcuts meant for an app, not leader keys; Shift is ignored.
        guard press.modifiers.isDisjoint(with: [.command, .option, .control]) else { return .noMatch(press) }
        let keys = typed + [press.key]
        switch resolve(keys) {
        case .prefix(let options):
            typed = keys
            return .options(options)
        case .noMatch:
            return .noMatch(press)
        case .command(let id, let argument):
            typed = []
            let repeats = lingering.map { $0.command == id && $0.argument == argument } ?? false
            return .run(Run(command: id, argument: argument,
                            repeatIndex: repeats ? lingering!.repeatIndex + 1 : 0, lingers: lingers(id)))
        }
    }

    /// Whether leader mode stays after `run` finished with `result`. A failed command cannot
    /// cycle, so only a successful lingering one keeps the mode.
    mutating func finished(_ run: Run, with result: CommandResult) -> Outcome {
        guard run.lingers, result == .done else {
            lingering = nil
            return .exit
        }
        lingering = run
        return .linger
    }
}
