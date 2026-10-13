import Contracts
import CoreGraphics

/// One open switcher. It owns the key capture from the shortcut press until the user
/// chooses a window or cancels, and reports which it was.
@MainActor
final class SwitcherSession {
    enum Outcome: Equatable {
        case chosen(WindowID)
        case cancelled
    }

    private let capture: any KeyCapture
    private let keys: SwitcherKeys
    private let hold: HoldModifiers
    private(set) var model: SwitcherModel?
    /// Steps asked for before the list was ready.
    private var pendingSteps = 0
    /// Set when the shortcut's modifiers were let go: the keys pressed before that still
    /// count, so the choice waits until the capture has handed them all over.
    private var choosesWhenKeysEnd = false
    private var tasks: [Task<Void, Never>] = []
    private var waiters: [CheckedContinuation<Outcome, Never>] = []
    private(set) var outcome: Outcome?

    /// Called after every selection change.
    var onSelectionChange: (WindowID?) -> Void = { _ in }
    /// Called once when the session ends, before anyone waiting hears the outcome.
    var onFinish: (Outcome) -> Void = { _ in }
    /// Whether a global point lies on the panel; a click anywhere else cancels.
    var isOnPanel: (CGPoint) -> Bool = { _ in false }

    init(capture: any KeyCapture, keys: SwitcherKeys, hold: HoldModifiers) {
        self.capture = capture
        self.keys = keys
        self.hold = hold
    }

    var isFinished: Bool { outcome != nil }

    /// Starts handling keys and `events`, which must have been subscribed before the shortcut
    /// could be let go. Keys pressed while the list was loading are handled first.
    func begin(with model: SwitcherModel, events: AsyncStream<InputEvent>) {
        guard !isFinished else { return }
        self.model = model
        if pendingSteps != 0 { model.move(by: pendingSteps) }
        let keyPresses = capture.keys
        tasks = [
            Task { [weak self] in
                for await press in keyPresses {
                    guard let self else { return }
                    if let action = self.keys.action(for: press) { self.perform(action) }
                }
                self?.keysEnded()
            },
            Task { [weak self] in
                for await event in events { self?.handle(event) }
            },
        ]
    }

    /// A shortcut press that reached the module instead of the capture, e.g. one made just
    /// before the capture started.
    func step(_ action: SwitcherAction) {
        guard model != nil else {
            if action == .forward { pendingSteps += 1 }
            if action == .backward { pendingSteps -= 1 }
            return
        }
        perform(action)
    }

    func perform(_ action: SwitcherAction) {
        guard !isFinished, let model else { return }
        switch action {
        case .forward:
            model.move(by: 1)
            onSelectionChange(model.selected?.id)
        case .backward:
            model.move(by: -1)
            onSelectionChange(model.selected?.id)
        case .choose:
            finish(choice)
        case .cancel:
            finish(.cancelled)
        }
    }

    func select(_ id: WindowID) {
        guard !isFinished, let model, model.selected?.id != id, model.item(id) != nil else { return }
        model.select(id)
        onSelectionChange(id)
    }

    func choose(_ id: WindowID) {
        guard !isFinished, let model, model.item(id) != nil else { return }
        model.select(id)
        finish(.chosen(id))
    }

    /// The shortcut's modifiers are up: choose once every key pressed before is handled.
    /// Only after `begin`, whose key loop hands those keys over.
    func chooseAfterPendingKeys() {
        guard !isFinished, !choosesWhenKeysEnd else { return }
        choosesWhenKeysEnd = true
        // Ending the capture gives the keyboard back; keys already captured stay in the stream.
        capture.end()
    }

    /// Drops a window that went away. Returns true when it was listed; an emptied list cancels.
    @discardableResult
    func windowGone(_ id: WindowID) -> Bool {
        guard !isFinished, let model, model.remove(id) else { return false }
        if model.items.isEmpty {
            finish(.cancelled)
        } else {
            onSelectionChange(model.selected?.id)
        }
        return true
    }

    func cancel() {
        finish(.cancelled)
    }

    func result() async -> Outcome {
        if let outcome { return outcome }
        return await withCheckedContinuation { waiters.append($0) }
    }

    private var choice: Outcome {
        model?.selected.map { .chosen($0.id) } ?? .cancelled
    }

    private func handle(_ event: InputEvent) {
        switch event {
        case .modifiersChanged(let modifiers):
            if hold.isReleased(in: modifiers) { chooseAfterPendingKeys() }
        case .mouseDown(let mouse):
            if !isOnPanel(mouse.location) { finish(.cancelled) }
        case .leaderTriggered, .shortcut, .mouseDragged, .mouseUp, .mouseMoved, .scroll:
            break
        }
    }

    /// The capture handed over its last key: after a release that means choose; otherwise
    /// someone else ended the capture and the switcher can no longer hear Esc, so it closes.
    private func keysEnded() {
        finish(choosesWhenKeysEnd ? choice : .cancelled)
    }

    private func finish(_ outcome: Outcome) {
        guard !isFinished else { return }
        self.outcome = outcome
        capture.end()
        for task in tasks { task.cancel() }
        tasks.removeAll()
        onFinish(outcome)
        let waiting = waiters
        waiters.removeAll()
        for waiter in waiting { waiter.resume(returning: outcome) }
    }
}
