import Contracts

/// Matches the keys typed after the leader trigger against the commands' leader keys.
enum LeaderMatcher {
    /// Options come in declaration order, once per key; a key that leads to more keys
    /// takes its group's title, or the first command's title when no group names it.
    /// Empty sequences are skipped so the leader key alone never runs a command.
    static func resolve(_ keys: [Key], commands: [CommandSpec], groups: [LeaderGroup]) -> LeaderResolution {
        var options: [LeaderOption] = []
        for spec in commands {
            for sequence in spec.leaderKeys where !sequence.patterns.isEmpty && sequence.patterns.count >= keys.count {
                let typed = zip(sequence.patterns, keys)
                guard typed.allSatisfy({ pattern, key in pattern.matches(key) }) else { continue }
                guard sequence.patterns.count > keys.count else {
                    let digit = typed.first { pattern, _ in pattern == .anyDigit }?.1.digitValue
                    return .command(spec.id, argument: digit)
                }
                let label = sequence.patterns[keys.count].description
                guard !options.contains(where: { $0.keys == label }) else { continue }
                let isGroup = sequence.patterns.count > keys.count + 1
                let prefix = Array(sequence.patterns.prefix(keys.count + 1))
                let group = isGroup ? groups.first { $0.prefix.patterns == prefix } : nil
                options.append(LeaderOption(keys: label, title: group?.title ?? spec.title, isGroup: isGroup))
            }
        }
        return options.isEmpty ? .noMatch : .prefix(options)
    }
}
