import Contracts
import CoreGraphics

/// The Dock icon a press landed on and what releasing it there does.
struct DockClickTarget {
    var item: DockItem
    var action: DockClickAction
}

/// The Dock click behaviour (design section 4.4). Input events are never swallowed, so the
/// Dock still sees the click; the action runs after the Dock has handled the release.
extension DockPreviewController {
    func beginPress(_ mouse: MouseEvent) {
        press = nil
        let behavior = settings.clickBehavior
        let point = mouse.location
        guard behavior != .systemDefault, DockClickGesture.isPlainLeftClick(mouse), mayBeOverDock(point),
              machine.panelFrame?.contains(point) != true else { return }
        let windows = self.windows
        let hovered = machine.hovered.flatMap { $0.iconFrame.contains(point) ? $0 : nil }
        // Read which app is in front right away: the Dock activates the clicked app when the button comes up.
        let frontmost = frontmostPID()
        let target = Task { @MainActor () -> DockClickTarget? in
            var item = hovered
            if item == nil { item = await windows.dockItem(at: point) }
            guard let item, item.iconFrame.contains(point), item.pid != nil, item.pid == frontmost else { return nil }
            var focused: WindowInfo?
            if behavior == .minimizeWindow, let id = await windows.focusedWindowID() { focused = await windows.window(id) }
            return DockClickAction.forClick(on: item, behavior: behavior, frontmostPID: frontmost, focused: focused)
                .map { DockClickTarget(item: item, action: $0) }
        }
        track { _ = await target.value }
        press = (DockClickGesture(start: point, time: scheduler.now), target)
    }

    func endPress(_ mouse: MouseEvent) {
        guard mouse.button == .left, let press else { return }
        self.press = nil
        let released = scheduler.now
        track { [weak self] in
            guard let target = await press.target.value, !Task.isCancelled, let self,
                  settings.clickBehavior != .systemDefault,
                  press.gesture.isClick(on: target.item.iconFrame, releasedAt: mouse.location, time: released) else { return }
            clickWork?.cancel()
            clickWork = scheduler.schedule(at: released + DockClickGesture.settleDelay) { [weak self] in
                self?.clickWork = nil
                self?.perform(target.action)
            }
        }
    }

    func cancelClick() {
        press?.target.cancel()
        press = nil
        clickWork?.cancel()
        clickWork = nil
    }

    private func perform(_ action: DockClickAction) {
        let windows = self.windows
        track {
            switch action {
            case .minimize(let id): _ = await windows.minimize(id)
            case .hide(let pid): _ = await windows.hideApplication(pid: pid)
            }
        }
    }
}
