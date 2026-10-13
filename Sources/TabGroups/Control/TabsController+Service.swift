import Contracts
import CoreGraphics
import CoreKit

/// What other modules may ask of tab groups (workspaces design 5.4).
extension TabsController {
    var snapshots: [TabGroupSnapshot] { book.all.map(Self.snapshot) }

    static func snapshot(of group: TabGroup) -> TabGroupSnapshot {
        TabGroupSnapshot(members: group.members, active: group.active, area: group.area, spaceID: group.spaceID)
    }

    /// Behind everything already queued, like a command.
    func form(members: [WindowID], active: WindowID, area: CGRect) async -> Result<TabGroupSnapshot, WindowError> {
        let request = FormRequest()
        _ = await serially {
            request.result = await self.formGroup(members: members, active: active, area: area)
            return .done
        }
        // A request still waiting when the queue stopped was never carried out.
        return request.result ?? .failure(.unsupported(Self.stoppedReason))
    }

    /// `members`, in that order, become one group filling `area`, whose top strip is the bar. Unlike
    /// `createGroup`, the area is given rather than taken from a window, so windows that already sit
    /// below a bar keep their size however often this runs. Windows that are gone, minimized or full
    /// screen, on another display or desktop than the one that will be in front, or unable to take
    /// the size (`TabGeometry.takesPlace`) are left out; the group returned says who is in. A failure means no group was made:
    /// the windows moved for it are back, though those taken out of other groups stay out. An area
    /// too small for the bar and a window fails without touching anything, and so does a group
    /// whose window in front is on a desktop that is not showing.
    func formGroup(members: [WindowID], active: WindowID, area: CGRect) async -> Result<TabGroupSnapshot, WindowError> {
        let member = TabGeometry.memberFrame(of: area, barHeight: barHeight)
        // An area that cannot hold the bar and a window is refused before anything is touched: no
        // write there would succeed, and by then the windows would be out of the groups they had.
        guard area.isFiniteRect, member.width >= 1, member.height >= TabGeometry.minimumMemberHeight else {
            return .failure(.rejected(L10n.text("tabgroups.this.area.cannot.fit.the.tab.bar")))
        }
        var order: [WindowID] = []
        for id in members where !order.contains(id) { order.append(id) }
        var open: [WindowInfo] = []
        for id in order {
            guard let info = await windows.window(id), !info.isMinimized, !info.isFullscreen else { continue }
            open.append(info)
        }
        // The window that will be in front says which display and desktop the group is on.
        if let front = open.first(where: { $0.id == active }) ?? open.first {
            // Focusing it would take the screen to its desktop, which nobody asked for. The
            // desktops are read now: a switch the caller just made is reported only once its
            // animation has ended, so what the last report left may be the desktop before.
            currentSpaces = Set(await windows.spaces().filter(\.isCurrent).map(\.id))
            if front.spaceIDs.count == 1, let space = front.spaceIDs.first, !currentSpaces.isEmpty,
               !currentSpaces.contains(space) {
                return .failure(.rejected(Self.offDesktopReason))
            }
            open = open.filter { canGroup($0, with: front, evenHidden: true) }
        }
        guard open.count >= 2 else { return .failure(.rejected(L10n.text("tabgroups.a.tab.group.requires.at.least.two"))) }
        // Already this very group, counting the windows that can be in it: a window that could not
        // take this frame before is not tried again, as when merging on snap. Only the tab in front
        // may change; anything else makes the group afresh, which checks that the windows fit.
        let able = open.map(\.id).filter { id in !(refused[id].map { TabGeometry.coincides($0, member) } ?? false) }
        if let first = able.first, let existing = book.group(containing: first), existing.members == able,
           TabGeometry.same(existing.area, area) {
            return .success(await show(existing, front: active))
        }
        // Out of their old groups first. A pair one of them leaves ends, and its other window is
        // owed the pair's whole area: it gets that only if it cannot be placed.
        let placing = Set(open.map(\.id))
        var homes: [WindowID: CGRect] = [:]
        for info in open where book.group(containing: info.id) != nil {
            if let owed = await leave(info.id, placing: placing) { homes[owed.window] = owed.area }
        }
        var fitted: [WindowInfo] = []
        for info in open {
            if await place(info, at: member, home: homes[info.id]) { fitted.append(info) }
        }
        // The book makes no group of fewer than two windows.
        guard let front = fitted.first(where: { $0.id == active }) ?? fitted.first,
              let group = book.create(members: fitted.map(\.id), active: front.id, area: area,
                                      displayID: display(around: area)?.id ?? front.displayID,
                                      spaceID: front.spaceIDs.count == 1 ? front.spaceIDs.first : nil) else {
            // No group: like `createGroup`, leave the windows as they were found.
            for info in fitted { await putBack(info.id, to: homes[info.id] ?? info.frame) }
            return .failure(.rejected(L10n.text("tabgroups.the.window.s.minimum.size.exceeds.this")))
        }
        for var info in fitted {
            info.frame = member
            infos[info.id] = info
        }
        log.note("\(group.id)：按给定区域合组，\(group.members.count) 个窗口")
        markUsed(group.id)
        return .success(await show(group, front: front.id))
    }

    /// Brings `front`'s tab forward, or the first tab when `front` is not in the group, and says
    /// what the group is now. The group stands even if its window could not be focused: another
    /// application may take the focus first, as while a workspace's applications are still
    /// launching. The check that follows then takes whichever window is in front as the tab.
    private func show(_ group: TabGroup, front: WindowID) async -> TabGroupSnapshot {
        _ = await activate(group.members.contains(front) ? front : group.members[0], in: group.id)
        scheduleReconcile()
        return Self.snapshot(of: book.group(group.id) ?? group)
    }
}

/// Carries a request's answer out of the queue, whose jobs answer as commands do.
@MainActor
private final class FormRequest {
    var result: Result<TabGroupSnapshot, WindowError>?
}
