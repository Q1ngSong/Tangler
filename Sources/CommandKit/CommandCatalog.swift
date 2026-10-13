import Contracts
import CoreKit
import Foundation

/// Checks a complete set of command declarations and renders COMMANDS.md (design section 6).
public enum CommandCatalog {
    /// Every problem in `specs` and `groups`; empty means the declarations agree with each other.
    public static func validate(_ specs: [CommandSpec], groups: [LeaderGroup] = []) -> [String] {
        var problems: [String] = []
        var seen: Set<CommandID> = []
        for spec in specs {
            if !seen.insert(spec.id).inserted { problems.append("\(spec.id)：ID 重复") }
            if spec.id.modulePrefix != spec.module.rawValue { problems.append("\(spec.id)：ID 应以 \(spec.module). 开头") }
            if spec.title.trimmingCharacters(in: .whitespaces).isEmpty {
                problems.append("\(spec.id)：缺少中文名")
            } else if TextMatcher.match(TextMatcher.initials(of: spec.title), in: spec.title) == nil {
                problems.append("\(spec.id)：用拼音首字母搜不到「\(spec.title)」")
            }
            let hasLeaderKeys = !spec.leaderKeys.isEmpty
            if spec.entryPoints.contains(.leader) && !hasLeaderKeys {
                problems.append("\(spec.id)：登记了 leader 入口却没有键位")
            }
            if hasLeaderKeys && !spec.entryPoints.contains(.leader) {
                problems.append("\(spec.id)：有总入口键却没有登记 leader 入口")
            }
            for sequence in spec.leaderKeys {
                if sequence.patterns.isEmpty { problems.append("\(spec.id)：键位为空") }
                if sequence.patterns.contains(.key(.escape)) { problems.append("\(spec.id)：Esc 保留给退出入口模式") }
            }
        }

        let sequences = specs.flatMap { spec in spec.leaderKeys.map { (id: spec.id, keys: $0) } }
        for i in sequences.indices {
            for j in sequences.indices where j > i && overlaps(sequences[i].keys, sequences[j].keys) {
                problems.append(keyConflict(sequences[i], sequences[j]))
            }
        }

        problems += groupProblems(sequences: specs.flatMap { spec in spec.leaderKeys.map { (spec: spec, keys: $0) } },
                                  groups: groups)

        var shortcutOwners: [KeyChord: CommandID] = [:]
        for spec in specs {
            guard let chord = spec.globalShortcut else { continue }
            if let owner = shortcutOwners[chord] {
                problems.append(shortcutConflict(owner, spec.id, chord))
            } else {
                shortcutOwners[chord] = spec.id
            }
        }
        return problems
    }

    /// COMMANDS.md: one row per command, modules in the given order, commands in declaration order,
    /// followed by the leader groups. `handWritten` is a part people maintain, e.g. the macOS
    /// features beside the commands: the text of the file named `file`, copied in as it is after
    /// the generated tables, and named in the note at the top as the file to edit.
    public static func markdownTable(_ specs: [CommandSpec], groups: [LeaderGroup] = [],
                                     modules: [(id: ModuleID, name: String)],
                                     handWritten: (file: String, text: String)? = nil) -> String {
        let regenerate = "运行 `scripts/update-commands.sh`"
        let note = handWritten.map {
            "本文件请勿手改。“命令”和“键位分组”两张表由各功能模块的命令声明生成；其后的内容原样取自 `\($0.file)`，"
                + "要改就改那个文件。改了声明或那个文件后\(regenerate)。"
        } ?? "由各功能模块的命令声明生成，请勿手改。改了声明后\(regenerate)。"
        var lines = [
            "# Tangler 命令总表",
            "",
            note,
            "",
            "| 命令 | 模块 | 名称 | 总入口键 | 全局快捷键 | 搜索面板 | 菜单栏 | 作用对象 |",
            "|---|---|---|---|---|---|---|---|",
        ]
        for module in modules {
            for spec in specs where spec.module == module.id {
                let leader = spec.leaderKeys.isEmpty ? "—" : spec.leaderKeys.map(\.description).joined(separator: " / ")
                let shortcut = spec.globalShortcut?.description ?? "—"
                let palette = spec.entryPoints.contains(.palette) ? "是" : "否"
                let menu = spec.entryPoints.contains(.menuBar) ? "是" : "否"
                let target = spec.target == .focusedWindow ? "当前窗口" : "无"
                lines.append("| `\(spec.id)` | \(module.name) | \(spec.title) | \(leader) | \(shortcut) | \(palette) | \(menu) | \(target) |")
            }
        }
        if !groups.isEmpty {
            lines += ["", "## 键位分组", "", "| 前缀 | 模块 | 名称 |", "|---|---|---|"]
            for module in modules {
                for group in groups where group.module == module.id {
                    lines.append("| \(group.prefix) | \(module.name) | \(group.title) |")
                }
            }
        }
        if let text = handWritten?.text.trimmingCharacters(in: .newlines), !text.isEmpty {
            lines += ["", text]
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Every key that leads to more keys needs a group, owned by the module of the commands
    /// under it; every group needs at least one command under it.
    static func groupProblems(sequences: [(spec: CommandSpec, keys: KeySequence)], groups: [LeaderGroup]) -> [String] {
        var problems: [String] = []
        var byPrefix: [KeySequence: LeaderGroup] = [:]
        for group in groups {
            if group.title.trimmingCharacters(in: .whitespaces).isEmpty { problems.append("分组 \(group.prefix)：缺少名称") }
            if byPrefix[group.prefix] != nil {
                problems.append("分组 \(group.prefix) 重复")
            } else {
                byPrefix[group.prefix] = group
            }
        }
        for entry in sequences where entry.keys.patterns.count > 1 {
            for length in 1..<entry.keys.patterns.count {
                let prefix = KeySequence(Array(entry.keys.patterns.prefix(length)))
                guard let group = byPrefix[prefix] else {
                    problems.append("\(entry.spec.id)：\(prefix) 后面还有键，但没有声明分组名")
                    continue
                }
                if group.module != entry.spec.module {
                    problems.append("\(entry.spec.id)：分组 \(prefix) 属于 \(group.module)，不能放 \(entry.spec.module) 的命令")
                }
            }
        }
        for group in groups where !sequences.contains(where: { entry in
            entry.keys.patterns.count > group.prefix.patterns.count
                && Array(entry.keys.patterns.prefix(group.prefix.patterns.count)) == group.prefix.patterns
        }) {
            problems.append("分组 \(group.prefix) 下面没有命令")
        }
        return problems
    }

    /// Why `spec` cannot join the already registered `existing`, or nil: the pairwise part of
    /// `validate`, checked when a command registers at runtime.
    static func conflict(between spec: CommandSpec, and existing: [CommandSpec]) -> String? {
        for other in existing {
            for keys in other.leaderKeys {
                if let clash = spec.leaderKeys.first(where: { overlaps(keys, $0) }) {
                    return keyConflict((other.id, keys), (spec.id, clash))
                }
            }
            if let chord = spec.globalShortcut, chord == other.globalShortcut {
                return shortcutConflict(other.id, spec.id, chord)
            }
        }
        return nil
    }

    static func keyConflict(_ first: (id: CommandID, keys: KeySequence), _ second: (id: CommandID, keys: KeySequence)) -> String {
        L10n.text("commandkit.keyConflict", first.id.rawValue, first.keys.description, second.id.rawValue, second.keys.description)
    }

    static func shortcutConflict(_ first: CommandID, _ second: CommandID, _ chord: KeyChord) -> String {
        L10n.text("commandkit.shortcutConflict", first.rawValue, second.rawValue, chord.description)
    }

    /// True when the sequences are equal or one is a prefix of the other, position by position.
    static func overlaps(_ a: KeySequence, _ b: KeySequence) -> Bool {
        let shared = min(a.patterns.count, b.patterns.count)
        guard shared > 0 else { return false }
        return zip(a.patterns.prefix(shared), b.patterns.prefix(shared)).allSatisfy { pair in overlap(pair.0, pair.1) }
    }

    static func overlap(_ a: KeyPattern, _ b: KeyPattern) -> Bool {
        switch (a, b) {
        case (.anyDigit, .anyDigit): return true
        case (.anyDigit, .key(let key)), (.key(let key), .anyDigit): return key.digitValue != nil
        case (.key(let first), .key(let second)): return first == second
        }
    }
}
