import Contracts
import CoreGraphics
import CoreKit

/// The handlers behind the layout commands (design section 4.2). Each one changes only the
/// target window: the one focused when the leader key or the palette opened, or for a
/// global shortcut the focused window.
@MainActor
final class LayoutCommandRunner {
    private let windows: any WindowService
    private let mover: WindowMover
    var settings = LayoutSettings.defaultValue

    init(windows: any WindowService, mover: WindowMover) {
        self.windows = windows
        self.mover = mover
    }

    func run(_ command: LayoutCommand, context: CommandContext) async -> CommandResult {
        await mover.serially { [self] in
            do {
                return try await perform(command, context: context)
            } catch {
                return (error as? CommandRefusal)?.result ?? .failed(reason: "\(error)")
            }
        }
    }

    private func perform(_ command: LayoutCommand, context: CommandContext) async throws -> CommandResult {
        if case .moveToDesktop = command, !windows.capabilities.contains(.moveAcrossSpaces) {
            throw CommandRefusal.unavailable(windows.unavailableReason(for: .moveAcrossSpaces) ?? L10n.text("windowlayout.this.mac.cannot.move.windows.between.desktops"))
        }
        let window = try await targetWindow(context)
        switch command {
        case .place(let action):
            return try await place(window, action, repeatIndex: context.repeatIndex)
        case .goBack:
            return try await goBack(window)
        case .moveToDisplay(let direction):
            return try await moveToDisplay(window, direction)
        case .moveToDesktop(let step):
            if case .number = step { return try await moveToDesktop(window, .number(context.argument)) }
            return try await moveToDesktop(window, step)
        }
    }

    private func targetWindow(_ context: CommandContext) async throws -> WindowInfo {
        guard windows.isAuthorized else { throw CommandRefusal.unavailable(L10n.text("commandpalette.accessibility.access.is.required")) }
        var id = context.targetWindow
        if id == nil { id = await windows.focusedWindowID() }
        guard let id else { throw CommandRefusal.failed(L10n.text("windowlayout.no.window.available.to.operate.on")) }
        guard let window = await windows.window(id) else { throw CommandRefusal.failed(L10n.text("tabgroups.the.window.could.not.be.found.it")) }
        guard !window.isFullscreen else { throw CommandRefusal.failed(L10n.text("windowlayout.full.screen.windows.cannot.be.moved")) }
        guard !window.isMinimized else { throw CommandRefusal.failed(L10n.text("windowlayout.the.window.is.minimized")) }
        return window
    }

    private func display(of window: WindowInfo, in displays: [DisplayInfo]) throws -> DisplayInfo {
        guard let display = DisplayLookup.display(for: window, in: displays) else { throw CommandRefusal.failed(L10n.text("windowlayout.could.not.read.the.display.list")) }
        return display
    }

    private func place(_ window: WindowInfo, _ action: LayoutAction, repeatIndex: Int) async throws -> CommandResult {
        let bounds = try display(of: window, in: await windows.displays()).visibleFrame
        let frame = LayoutGeometry.frame(for: action, window: window.frame, in: bounds, repeatIndex: repeatIndex,
                                         gap: settings.gapPoints)
        let kind: MoveKind = action == .center ? .reposition : .snap
        return await mover.move(window, to: frame, within: bounds, kind: kind).commandResult
    }

    private func goBack(_ window: WindowInfo) async throws -> CommandResult {
        guard var previous = mover.takePrevious(window.id, current: window.frame) else {
            throw CommandRefusal.failed(L10n.text("windowlayout.this.window.has.no.earlier.position"))
        }
        let displays = await windows.displays()
        // The display it was on may be gone; then it comes back on the display it is on now.
        if !displays.contains(where: { $0.frame.intersects(previous) }) {
            let bounds = try display(of: window, in: displays).visibleFrame
            previous = LayoutGeometry.rounded(RectMath.clamp(previous, to: bounds))
        }
        return await mover.move(window, to: previous, within: nil, kind: .undo).commandResult
    }

    private func moveToDisplay(_ window: WindowInfo, _ direction: Direction) async throws -> CommandResult {
        let displays = await windows.displays()
        let source = try display(of: window, in: displays)
        guard let target = DisplayNeighbors.neighbor(of: source, toward: direction, among: displays) else {
            throw CommandRefusal.failed(L10n.text("windowlayout.no.other.display.in.this.direction", String(describing: (direction.sideName))))
        }
        let frame = DisplayNeighbors.transfer(window.frame, from: source.visibleFrame, to: target.visibleFrame)
        return await mover.move(window, to: frame, within: target.visibleFrame, kind: .reposition).commandResult
    }

    private func moveToDesktop(_ window: WindowInfo, _ step: DesktopStep) async throws -> CommandResult {
        let spaces = await windows.spaces()
        guard !spaces.isEmpty else {
            throw CommandRefusal.unavailable(windows.unavailableReason(for: .spaceList) ?? L10n.text("windowkit.could.not.read.the.desktop.list"))
        }
        switch DesktopTargets.resolve(step, for: window, among: spaces) {
        case .stay:
            return .done
        case .impossible(let reason):
            return .failed(reason: reason)
        case .move(let space):
            switch await windows.move(window.id, toSpace: space) {
            case .success: return .done
            case .failure(let error): return error.commandResult
            }
        }
    }
}
