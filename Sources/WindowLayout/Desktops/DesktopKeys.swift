import Contracts
import CoreKit

/// One of the system's desktop shortcuts and the desktop command that answers it.
struct DesktopKey: Equatable, Sendable {
    /// The id the chord is held under in `InputService`.
    var id: String
    var chord: KeyChord
    var command: DesktopCommand
    /// The digit for "切到第 N 个桌面"; 0 stands for the tenth desktop.
    var argument: Int?

    /// ⌃← and ⌃→ for the desktop to the left and right, ⌃1…⌃9 and ⌃0 for the N-th: the keys
    /// macOS gives "向左移动一个空间", "向右移动一个空间" and "切换到桌面 N".
    static let all: [DesktopKey] = [
        DesktopKey(id: "layout.desktopKey.previous", chord: KeyChord(.left, modifiers: .control),
                   command: .switchTo(.previous)),
        DesktopKey(id: "layout.desktopKey.next", chord: KeyChord(.right, modifiers: .control),
                   command: .switchTo(.next)),
    ] + ([1, 2, 3, 4, 5, 6, 7, 8, 9, 0] as [Int]).map { digit in
        DesktopKey(id: "layout.desktopKey.\(digit)", chord: KeyChord(.digit(digit), modifiers: .control),
                   command: .switchTo(.number(nil)), argument: digit)
    }
}

/// Takes the system's desktop shortcuts over while turned on: the chords are held in
/// `InputService`, which swallows them before the system sees them, and each press runs the
/// desktop command the D group runs. They are not commands of their own, so the registry does
/// not hold them. Presses run one after the other, each from the desktop the one before reached.
@MainActor
final class DesktopKeys {
    private let input: any InputService
    private let run: @MainActor (DesktopCommand, CommandContext) async -> CommandResult
    private let log = DiagnosticLog("desktop-keys")
    private var listening: Task<Void, Never>?

    init(input: any InputService, run: @escaping @MainActor (DesktopCommand, CommandContext) async -> CommandResult) {
        self.input = input
        self.run = run
    }

    var isEnabled: Bool { listening != nil }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        guard enabled else {
            listening?.cancel()
            listening = nil
            for key in DesktopKey.all { input.unregisterShortcut(id: key.id) }
            return
        }
        // Subscribed before the chords are held, so no press is lost.
        let events = input.events(.shortcuts)
        for key in DesktopKey.all {
            do {
                try input.registerShortcut(key.chord, id: key.id)
            } catch {
                // Another shortcut has the chord; that one keeps it.
                log.problem("桌面快捷键 \(key.chord) 没能注册：\(error)")
            }
        }
        listening = Task { [weak self] in
            for await event in events {
                guard case .shortcut(let id) = event, let key = DesktopKey.all.first(where: { $0.id == id }) else { continue }
                await self?.pressed(key)
            }
        }
    }

    private func pressed(_ key: DesktopKey) async {
        // A press that arrived just before the keys were turned off.
        guard isEnabled else { return }
        switch await run(key.command, CommandContext(argument: key.argument)) {
        case .done: break
        case .unavailable(let reason), .failed(let reason): log.note("\(key.chord)：\(reason)")
        }
    }
}
