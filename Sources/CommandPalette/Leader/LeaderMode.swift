import Contracts
import CoreGraphics
import CoreKit
import Foundation

/// Leader mode (design section 4.2). After the leader trigger, keys go to the registry's leader
/// resolution instead of the frontmost app, and the hint panel shows what can come next.
///
/// With the hold trigger, leader mode starts as right Command goes down. While it is held,
/// keys run at once, nothing times out, and the hints appear only after a pause, so a quick
/// chord never flashes them. Letting go ends leader mode once a command ran; let go without a
/// key, it stays as after a tap.
@MainActor
final class LeaderMode {
    /// How long a held leader key rests before the hints appear.
    nonisolated static let holdHintDelay: Double = 0.4

    /// From the settings; read whenever the linger period starts.
    var lingerSeconds = PaletteSettings.defaultValue.effectiveLingerSeconds
    /// From the settings: whether the trigger is holding right Command.
    var holdsTrigger = false
    /// Told about every command leader mode runs, for the palette's recently-used order.
    var onRun: ((CommandID) -> Void)?
    /// Off while the module is stopped: triggers are ignored and late results stay silent.
    var isEnabled = false {
        didSet { if !isEnabled { exit() } }
    }

    private let windows: any WindowService
    private let input: any InputService
    private let commands: any CommandRegistry
    private let hud: LeaderHUD
    private let areas: OverlayAreaFinder
    private let scheduler: any Scheduling
    private var active: Active?
    private var lastSessionID = 0
    private let log = DiagnosticLog("leader")

    private struct Active {
        let id: Int
        let capture: any KeyCapture
        /// Reads clicks and modifier changes.
        let events: Task<Void, Never>
        /// The window focused at the trigger; every command of the session acts on it.
        var target: WindowID?
        var area = CGRect.zero
        /// The target and area are known, so the hints can show.
        var isReady = false
        var session = LeaderSession()
        var hints: LeaderHints?
        var timer: ScheduledWork?
        /// Right Command is held as the leader key.
        var isHeld = false
        /// A command ran while it was held: letting go ends leader mode.
        var ranCommand = false
        /// Shows the hints once a held key has rested.
        var hintTimer: ScheduledWork?
    }

    init(context: ModuleContext, hud: LeaderHUD, areas: OverlayAreaFinder, scheduler: any Scheduling) {
        windows = context.windows
        input = context.input
        commands = context.commands
        self.hud = hud
        self.areas = areas
        self.scheduler = scheduler
    }

    var isActive: Bool { active != nil }

    /// Starts leader mode, or leaves it when it is on: tapping the leader key again leaves.
    func toggle() async {
        guard isEnabled else { return }
        if active != nil {
            exit()
        } else {
            await enter()
        }
    }

    func exit() {
        guard let active else { return }
        log.trace("退出入口模式 #\(active.id)")
        self.active = nil
        active.timer?.cancel()
        active.hintTimer?.cancel()
        active.events.cancel()
        // Ending the capture finishes its key stream, which ends the task reading it. Cancelling
        // that task instead would also cancel a command it may still be running.
        active.capture.end()
        hud.hide()
    }

    private func exit(session id: Int) {
        if active?.id == id { exit() }
    }

    private func enter() async {
        lastSessionID += 1
        let id = lastSessionID
        let entered = ContinuousClock.now
        log.trace("进入入口模式 #\(id)")
        // Capture before anything else: keys typed while the target is looked up wait in it.
        let capture = input.beginKeyCapture()
        let events = input.events([.mouseButtons, .modifiers])
        active = Active(id: id, capture: capture, events: Task { [weak self] in
            for await event in events {
                switch event {
                case .mouseDown:
                    // A click means the user went on with something else.
                    self?.exit(session: id)
                case .modifiersChanged(let modifiers):
                    if !modifiers.contains(.command) { self?.released(session: id) }
                case .leaderTriggered, .shortcut, .mouseDragged, .mouseUp, .mouseMoved, .scroll:
                    break
                }
            }
        })
        // Asked of the event tap, not the system's modifier state, which has not caught up with
        // the key going down yet; and asked after subscribing, so a release from now on is seen.
        active?.isHeld = holdsTrigger && input.isLeaderKeyHeld
        let target = await windows.focusedWindowID()
        let area = await areas.area(for: target)
        guard active?.id == id else { return }
        active?.target = target
        active?.area = area
        active?.isReady = true
        log.trace("入口模式 #\(id) 目标窗口 \(target.map { String($0.rawValue) } ?? "无")，查找用时 \(entered.duration(to: .now))"
                  + (active?.isHeld == true ? "，按住入口键" : ""))
        guard let options = options(after: []) else {
            log.problem("入口模式没有可用的命令")
            exit()
            return
        }
        present(LeaderHints(options: options, title: nil, footer: footer, isFaded: false))
        let keys = capture.keys
        Task { [weak self] in
            for await press in keys {
                await self?.handle(press, session: id)
            }
            self?.exit(session: id)
        }
    }

    private func handle(_ press: KeyPress, session id: Int) async {
        guard var current = active, current.id == id else { return }
        let commands = self.commands
        let step = current.session.press(press, resolve: { commands.resolveLeader($0) }, lingers: { command in
            commands.commands.first { $0.id == command }?.lingersAfterRun ?? false
        })
        active = current
        log.trace("入口模式按键 \(KeyChord(press.key, modifiers: press.modifiers)) → \(Self.describe(step))")
        if step != .ignore { active?.hintTimer?.cancel() }
        switch step {
        case .ignore:
            return
        case .exit:
            exit()
        case .options(let options):
            present(LeaderHints(options: options, title: groupTitle(for: current.session.typed),
                                footer: footer, isFaded: false))
            if current.session.timesOut { restartTimer() }
        case .noMatch(let press):
            // Shown at once, even while the key is held: the user is looking for a key.
            let typed = current.session.typed
            var hints = current.hints ?? LeaderHints(options: options(after: typed) ?? [],
                                                     title: typed.isEmpty ? nil : groupTitle(for: typed),
                                                     footer: footer, isFaded: false)
            hints.footer = LeaderText.noSuchKey(press)
            show(hints)
        case .run(let run):
            await perform(run, session: id)
        }
    }

    private func perform(_ run: LeaderSession.Run, session id: Int) async {
        guard let current = active, current.id == id else { return }
        active?.timer?.cancel()
        active?.timer = nil
        if current.isHeld { active?.ranCommand = true }
        let context = CommandContext(targetWindow: current.target, argument: run.argument, repeatIndex: run.repeatIndex)
        let title = commands.commands.first { $0.id == run.command }?.title
        onRun?(run.command)
        guard run.lingers else {
            // Leave first, so a command that brings its own UI, such as the palette or the
            // window picker, gets the keyboard, and a slow one does not hold it.
            exit()
            report(await commands.perform(run.command, context: context), title: title, area: current.area)
            return
        }
        let result = await commands.perform(run.command, context: context)
        guard var latest = active, latest.id == id else {
            report(result, title: title, area: current.area)
            return
        }
        let outcome = latest.session.finished(run, with: result)
        active = latest
        switch outcome {
        case .linger:
            present(LeaderHints(options: options(after: []) ?? [], title: title,
                                footer: latest.isHeld ? LeaderText.release : LeaderText.linger(lingerSeconds),
                                isFaded: true))
            restartTimer()
        case .exit:
            exit()
            report(result, title: title, area: current.area)
        }
    }

    private static func describe(_ step: LeaderSession.Step) -> String {
        switch step {
        case .options(let options): return "等下一个键（\(options.count) 个选项）"
        case .run(let run): return "执行 \(run.command.rawValue)"
        case .noMatch: return "没有这个键"
        case .exit: return "退出"
        case .ignore: return "忽略按住不放的重复"
        }
    }

    /// Let go of ⌘. Once a command ran, that is the end; with nothing run yet, leader mode stays
    /// and shows its hints, as after a tap.
    private func released(session id: Int) {
        guard var current = active, current.id == id, current.isHeld else { return }
        current.isHeld = false
        current.hintTimer?.cancel()
        current.hintTimer = nil
        active = current
        log.trace("松开入口键\(current.ranCommand ? "，结束" : "，入口模式保留")")
        guard !current.ranCommand else { return exit() }
        // Before the target is known, entering shows the hints itself.
        guard current.isReady else { return }
        let typed = current.session.typed
        present(LeaderHints(options: options(after: typed) ?? [], title: typed.isEmpty ? nil : groupTitle(for: typed),
                            footer: LeaderText.leave, isFaded: current.session.isFaded))
    }

    /// While the key is held: how to end leader mode, else how to leave it.
    private var footer: String {
        active?.isHeld == true ? LeaderText.release : LeaderText.leave
    }

    /// Shows the hints now, or, while the key is held, once it has rested.
    private func present(_ hints: LeaderHints) {
        guard let current = active else { return }
        guard current.isHeld else { return show(hints) }
        current.hintTimer?.cancel()
        let id = current.id
        active?.hintTimer = scheduler.schedule(after: Self.holdHintDelay) { [weak self] in
            guard let self, self.active?.id == id, self.active?.isHeld == true else { return }
            self.show(hints)
        }
    }

    private func restartTimer() {
        // A held key keeps leader mode: the user is still at it.
        guard let id = active?.id, active?.isHeld != true else { return }
        active?.timer?.cancel()
        active?.timer = scheduler.schedule(after: lingerSeconds) { [weak self] in self?.exit(session: id) }
    }

    private func show(_ hints: LeaderHints) {
        guard let area = active?.area else { return }
        active?.hints = hints
        hud.showHints(hints, in: area)
    }

    private func report(_ result: CommandResult, title: String?, area: CGRect) {
        guard isEnabled else { return }
        hud.report(result, title: title, in: area)
    }

    private func options(after keys: [Key]) -> [LeaderOption]? {
        guard case .prefix(let options) = commands.resolveLeader(keys) else { return nil }
        return options
    }

    /// The name of the group the typed keys open, e.g. "移到其他显示器" after D.
    private func groupTitle(for keys: [Key]) -> String {
        let group = commands.groups.first { group in
            group.prefix.patterns.count == keys.count
                && zip(group.prefix.patterns, keys).allSatisfy { pattern, key in pattern.matches(key) }
        }
        return group?.title ?? keys.map(\.symbol).joined(separator: " ")
    }
}

/// What the hint panel says besides the keys.
enum LeaderText {
    static var leave: String { L10n.text("leader.leave") }
    static var release: String { L10n.text("leader.release") }

    static func linger(_ seconds: Double) -> String {
        L10n.text("leader.linger", seconds.formatted(.number.precision(.fractionLength(0...2)).locale(L10n.current.locale)))
    }

    static func noSuchKey(_ press: KeyPress) -> String {
        L10n.text("leader.noSuchKey", String(describing: KeyChord(press.key, modifiers: press.modifiers)))
    }
}
