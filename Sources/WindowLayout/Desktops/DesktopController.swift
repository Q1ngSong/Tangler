import CoreKit
import Contracts

/// The handlers behind the desktop commands. Cleanup covers all displays; other commands use
/// the target window's display, or the main display when there is no window. Whether the Mac can do it is
/// left to the window service, whose reason is shown. Before a desktop is removed, whoever
/// owns it is told.
@MainActor
final class DesktopController {
    private let windows: any WindowService
    private var isCleaning = false
    /// Whoever desktops may belong to, when the module that knows is running.
    private let owner: @MainActor () -> (any DesktopOwnership)?

    init(windows: any WindowService, owner: @escaping @MainActor () -> (any DesktopOwnership)? = { nil }) {
        self.windows = windows
        self.owner = owner
    }

    func run(_ command: DesktopCommand, context: CommandContext) async -> CommandResult {
        if command == .cleanEmpty { return await cleanEmpty() }
        guard let display = await currentDisplay(context) else { return .failed(reason: L10n.text("windowlayout.could.not.read.the.display.list")) }
        let spaces = await windows.spaces()
        switch command {
        case .cleanEmpty: return await cleanEmpty()
        case .new:
            return await add(on: DesktopPicker.desktops(on: display, among: spaces).first?.displayID ?? display)
        case .remove:
            guard !spaces.isEmpty else { return noDesktopList }
            guard let current = DesktopPicker.current(on: display, among: spaces) else {
                return .failed(reason: DesktopPicker.notOnADesktop)
            }
            // A workspace that owns the desktop saves and lets go of it first. A display's last
            // desktop is not removed, so nobody is told to let go of that.
            if DesktopPicker.desktops(on: display, among: spaces).count > 1 {
                await owner()?.desktopWillBeRemoved(current.id)
            }
            return result(of: await windows.removeSpace(current.id))
        case .switchTo(let choice):
            guard !spaces.isEmpty else { return noDesktopList }
            var choice = choice
            if case .number = choice { choice = .number(context.argument) }
            switch DesktopPicker.pick(choice, on: display, among: spaces) {
            case .stay: return .done
            case .impossible(let reason): return .failed(reason: reason)
            case .go(let space): return result(of: await windows.switchTo(space: space, focusing: nil))
            }
        }
    }

    /// All displays, by stable Space IDs. Current desktops go last so an entirely empty display
    /// keeps the desktop it was showing. Every iteration reads the remaining siblings again.
    private func cleanEmpty() async -> CommandResult {
        guard !isCleaning else { return .failed(reason: L10n.text("windowlayout.empty.desktop.cleanup.is.already.running")) }
        guard windows.capabilities.contains(.manageSpaces), windows.isAuthorized else {
            return .unavailable(reason: windows.isAuthorized
                ? windows.unavailableReason(for: .manageSpaces) ?? L10n.text("windowlayout.cannot.manage.desktops") : L10n.text("commandpalette.accessibility.access.is.required"))
        }
        isCleaning = true
        defer { isCleaning = false }
        let initial = await windows.spaces()
        guard !initial.isEmpty else { return noDesktopList }
        let ordinary = initial.filter { !$0.isFullscreen }
        let candidates = ordinary.reversed().filter { !$0.isCurrent } + ordinary.filter(\.isCurrent)
        var removed = 0
        var unknown = 0
        for candidate in candidates {
            if Task.isCancelled { return .failed(reason: L10n.text("windowlayout.empty.desktops.removed.cleanup.was.cancelled", String(describing: (removed)))) }
            let latest = await windows.spaces()
            guard !latest.isEmpty else { return .failed(reason: L10n.text("windowlayout.empty.desktops.removed.could.not.read.the", String(describing: (removed)))) }
            guard let target = latest.first(where: { $0.id == candidate.id && !$0.isFullscreen }),
                  latest.filter({ $0.displayID == target.displayID && !$0.isFullscreen }).count > 1 else { continue }
            guard let empty = await windows.isSpaceEmpty(target.id) else { unknown += 1; continue }
            guard empty else { continue }
            if Task.isCancelled { return .failed(reason: L10n.text("windowlayout.empty.desktops.removed.cleanup.was.cancelled", String(describing: (removed)))) }
            await owner()?.desktopWillBeRemoved(target.id)
            if Task.isCancelled { return .failed(reason: L10n.text("windowlayout.empty.desktops.removed.cleanup.was.cancelled", String(describing: (removed)))) }
            switch await windows.removeSpaceIfEmpty(target.id) {
            case .success: removed += 1
            case .failure(let error):
                let reason: String
                switch error.commandResult {
                case .failed(let text), .unavailable(let text): reason = text
                case .done: reason = L10n.text("windowlayout.removal.failed")
                }
                return .failed(reason: L10n.text("windowlayout.empty.desktops.removed", String(describing: (removed)), String(describing: (reason))))
            }
        }
        if unknown > 0 {
            return .failed(reason: L10n.text("windowlayout.empty.desktops.removed.kept.desktops.with.uncertain", String(describing: (removed)), String(describing: (unknown))))
        }
        return .done
    }

    private var noDesktopList: CommandResult {
        .unavailable(reason: windows.unavailableReason(for: .spaceList) ?? L10n.text("windowkit.could.not.read.the.desktop.list"))
    }

    private func add(on display: DisplayID) async -> CommandResult {
        switch await windows.addSpace(on: display, switching: true) {
        case .failure(let error): return error.commandResult
        case .success(let created):
            return created.isCurrent ? .done : .failed(reason: L10n.text("windowlayout.created.desktop.but.could.not.switch.to", String(describing: (created.index))))
        }
    }

    private func result(of outcome: Result<Void, WindowError>) -> CommandResult {
        switch outcome {
        case .success: return .done
        case .failure(let error): return error.commandResult
        }
    }

    private func currentDisplay(_ context: CommandContext) async -> DisplayID? {
        let displays = await windows.displays()
        var id = context.targetWindow
        if id == nil { id = await windows.focusedWindowID() }
        if let id, let window = await windows.window(id),
           let display = DisplayLookup.display(for: window, in: displays) {
            return display.id
        }
        return DisplayLookup.main(in: displays)?.id
    }
}
