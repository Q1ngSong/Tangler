import AppKit
import Carbon
import Contracts
import CoreKit
import Foundation

/// Global keyboard and mouse input through the app's only event tap (design section 3.3).
///
/// The App calls `start()` once the Accessibility permission is granted, and again after a
/// failed start once the user grants it. `stop()` removes the tap, ends every capture and
/// gives the system switcher back; quitting the app does the same. Everything else follows
/// `InputService` and may be called from any thread.
public final class SystemInputService: InputService, @unchecked Sendable {
    private let tap: any EventTapDriver
    private let switcher: SwitcherHotKeys
    private let clock: @Sendable () -> TimeInterval
    private let hub = EventHub()
    private let log = DiagnosticLog("input")

    /// Guards the routing state, which the tap thread reads for every event.
    private let lock = NSLock()
    private var router = InputRouter()
    private var captures: [Int: SystemKeyCapture] = [:]
    private var lastCaptureID = 0

    /// Serializes start and stop.
    private let lifecycle = NSLock()
    private let notifications: NotificationCenter
    private var terminationObserver: (any NSObjectProtocol)?

    /// The real service: the system event tap, the private hot key calls probed now, and
    /// the secure input state that password fields turn on.
    public convenience init() {
        self.init(tap: SystemEventTap(), hotKeys: SymbolicHotKeyFunctions.load(), hotKeyStore: .userDefaults,
                  clock: { ProcessInfo.processInfo.systemUptime },
                  isSecureInputActive: { IsSecureEventInputEnabled() })
    }

    init(tap: any EventTapDriver, hotKeys: SymbolicHotKeyFunctions?, hotKeyStore: HotKeyStateStore = .none,
         clock: @escaping @Sendable () -> TimeInterval,
         isSecureInputActive: @escaping @Sendable () -> Bool,
         notifications: NotificationCenter = .default) {
        self.tap = tap
        self.switcher = SwitcherHotKeys(functions: hotKeys, store: hotKeyStore)
        self.clock = clock
        self.notifications = notifications
        router.isSecureInputActive = isSecureInputActive
        terminationObserver = notifications.addObserver(forName: NSApplication.willTerminateNotification,
                                                        object: nil, queue: nil) { [weak self] _ in
            self?.stop()
        }
    }

    deinit {
        if let terminationObserver { notifications.removeObserver(terminationObserver) }
        stop()
        hub.finish()
    }

    // MARK: Lifecycle

    /// Whether the event tap is installed and enabled.
    public var isRunning: Bool { tap.isRunning }

    /// Whether the private call that turns off the system switcher was found at launch.
    public var canSuppressSystemSwitcher: Bool { switcher.isAvailable }

    /// Installs the event tap. False when the tap cannot be created, usually because the
    /// Accessibility permission is missing.
    @discardableResult
    public func start() -> Bool {
        lifecycle.withLock {
            if tap.isRunning { return true }
            lock.withLock { router.reset() }
            let started = tap.start(EventTapHandler(
                wantsMouseMoved: { [weak self] in self?.wantsMouseMoved ?? false },
                handle: { [weak self] event in self?.handle(event) ?? false },
                tapReenabled: { [weak self] in self?.tapReenabled() }))
            if started { log.note("事件监听已启动") } else { log.problem("事件监听启动失败，多半是缺少辅助功能权限") }
            return started
        }
    }

    /// Removes the tap, ends every capture and restores the system switcher hot keys.
    /// Registered shortcuts and the leader trigger stay for the next `start()`.
    public func stop() {
        lifecycle.withLock {
            tap.stop()
            for capture in lock.withLock({ Array(captures.values) }) {
                capture.end()
            }
            lock.withLock { router.reset() }
            switcher.restore()
            log.note("事件监听已停止")
        }
    }

    // MARK: InputService

    /// Whether the event tap can exist: true while it runs, otherwise a tap is created
    /// and removed again to find out. Never asks the Accessibility API, which WindowKit owns.
    public var isAuthorized: Bool { tap.isRunning || tap.canCreateTap() }

    public func events(_ filter: InputEventFilter) -> AsyncStream<InputEvent> {
        hub.stream(filter)
    }

    public var isLeaderKeyHeld: Bool {
        lock.withLock { router.leader.isHolding }
    }

    public func setLeaderTrigger(_ trigger: LeaderTrigger?) {
        lock.withLock { router.leader.trigger = trigger }
        log.note("总入口键：\(trigger.map { String(describing: $0) } ?? "无")")
    }

    /// Works without the permission and before `start()`: the chord is kept and takes effect
    /// once the tap runs. Only throws `InputError.shortcutInUse`.
    public func registerShortcut(_ chord: KeyChord, id: String) throws {
        do {
            try lock.withLock { try router.shortcuts.register(chord, id: id) }
            log.note("快捷键 \(chord) → \(id)")
        } catch {
            log.problem("快捷键 \(chord) 没能给 \(id)：\(error)")
            throw error
        }
    }

    public func unregisterShortcut(id: String) {
        lock.withLock { router.shortcuts.unregister(id: id) }
        log.trace("取消快捷键 \(id)")
    }

    /// While suspended, global shortcuts and the leader trigger are ignored and their keys
    /// reach the frontmost app, e.g. while the settings page records a chord. Key captures,
    /// mouse and modifier events are unaffected. Takes effect at once.
    public func setShortcutsSuspended(_ suspended: Bool) {
        lock.withLock { router.shortcutsSuspended = suspended }
        log.note(suspended ? "快捷键暂停" : "快捷键恢复")
    }

    /// Keys typed after the leader fired and before this call come first: leader mode starts
    /// its capture right after the trigger, and a quick key must not reach the app meanwhile.
    public func beginKeyCapture() -> any KeyCapture {
        let time = clock()
        let (capture, waiting) = lock.withLock { () -> (SystemKeyCapture, [KeyPress]) in
            lastCaptureID += 1
            let capture = SystemKeyCapture(id: lastCaptureID) { [weak self] id in self?.captureEnded(id) }
            captures[capture.id] = capture
            return (capture, router.beginCapture(capture.id, at: time))
        }
        log.trace("开始捕获按键 #\(capture.id)" + (waiting.isEmpty ? "" : "，先交给它 \(waiting.count) 个等着的键"))
        for press in waiting { capture.deliver(press) }
        return capture
    }

    public func setMouseMoveShield(_ region: CGRect?) {
        lock.withLock { router.mouseMoveShield = region }
        log.note(region.map { "拦下这块区域里的鼠标移动：\($0)" } ?? "不再拦鼠标移动")
    }

    @discardableResult
    public func setSystemSwitcherSuppressed(_ suppressed: Bool) -> Bool {
        let done = switcher.setSuppressed(suppressed)
        log.note("\(suppressed ? "关闭" : "恢复")系统 ⌘Tab：\(done ? "成功" : "失败")")
        return done
    }

    // MARK: Tap thread

    /// Pointer moves are taken from the system only when someone listens or a shield needs them.
    private var wantsMouseMoved: Bool {
        hub.wantsMouseMoved || lock.withLock { router.mouseMoveShield != nil }
    }

    private func handle(_ event: RawInputEvent) -> Bool {
        let time = clock()
        let (routing, capture) = lock.withLock { () -> (Routing, SystemKeyCapture?) in
            let routing = router.route(event, at: time)
            return (routing, routing.delivery.flatMap { captures[$0.captureID] })
        }
        trace(event, routing)
        if let delivery = routing.delivery { capture?.deliver(delivery.press) }
        for event in routing.events { hub.send(event) }
        return routing.swallow
    }

    /// Tab, Space, ` and Esc: the keys of the switcher, leader mode and palette.
    private static let tracedKeys: Set<UInt16> = [0x30, 0x31, 0x32, 0x35]

    /// Modifier changes, what the router made of them, and the few command keys while a
    /// modifier is held or a capture takes them. Plain typing is never logged.
    private func trace(_ event: RawInputEvent, _ routing: Routing) {
        switch event.kind {
        case .flagsChanged(let keyCode):
            log.trace("修饰键 keyCode=\(keyCode) flags=0x\(String(event.flags.rawValue, radix: 16))")
        case .keyDown(let keyCode, false) where Self.tracedKeys.contains(keyCode):
            let modifiers = Modifiers(eventFlags: event.flags).ignoringFunction
            guard !modifiers.isEmpty || routing.swallow else { break }
            log.trace("按键 \(modifiers)\(Key(keyCode: keyCode)) 吞掉=\(routing.swallow) 交给捕获=\(routing.delivery != nil)")
        default:
            break
        }
        for output in routing.events {
            switch output {
            case .leaderTriggered: log.trace("总入口键触发")
            case .shortcut(let id): log.trace("快捷键命中 \(id)")
            default: break
            }
        }
    }

    private func tapReenabled() {
        lock.withLock { router.reset() }
        log.note("事件监听被系统暂停过，已重新启用")
    }

    private func captureEnded(_ id: Int) {
        lock.withLock {
            router.endCapture(id)
            captures[id] = nil
        }
        log.trace("结束捕获按键 #\(id)")
    }
}
