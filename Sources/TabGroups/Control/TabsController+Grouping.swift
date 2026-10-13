import CoreKit
import Contracts
import CoreGraphics

/// Commands, making and taking apart groups, merging on snap, and dragging (tab groups design 4.2–4.7).
extension TabsController {
    // MARK: Commands

    func run(_ command: TabCommand, context: CommandContext) async -> CommandResult {
        switch command {
        case .mergeArea:
            return await mergeArea(target: context.targetWindow)
        case .addWindow:
            return await add(picked: pick(), target: context.targetWindow)
        case .next:
            return await step(1, target: context.targetWindow)
        case .previous:
            return await step(-1, target: context.targetWindow)
        case .select:
            return await select(context.argument, target: context.targetWindow)
        case .remove:
            guard let id = await resolve(context.targetWindow), book.group(containing: id) != nil else {
                return Self.notGrouped
            }
            return await detach(id)
        case .ungroup:
            guard let id = await resolve(context.targetWindow), let group = book.group(containing: id) else {
                return Self.notGrouped
            }
            await ungroup(group.id)
            return .done
        }
    }

    /// From the command handlers: behind everything already queued. Picking a window waits for the
    /// user outside the queue, once leader mode has ended, so Esc reaches the picker.
    func perform(_ command: TabCommand, context: CommandContext) async -> CommandResult {
        guard command == .addWindow else { return await serially { await self.run(command, context: context) } }
        let target = await resolve(context.targetWindow)
        Task { [weak self] in
            guard let self else { return }
            let picked = await self.pick()
            let result = await self.serially { await self.add(picked: picked, target: target) }
            if case .failed(let reason) = result { self.log.problem("点选加入失败：\(reason)") }
        }
        return .done
    }

    func resolve(_ target: WindowID?) async -> WindowID? {
        if let target { return target }
        return await windows.focusedWindowID()
    }

    func step(_ delta: Int, target: WindowID?) async -> CommandResult {
        guard let id = await resolve(target), let group = book.group(containing: id),
              let next = book.neighbour(of: group.active, step: delta) else { return Self.notGrouped }
        return await activate(next, in: group.id)
    }

    func select(_ digit: Int?, target: WindowID?) async -> CommandResult {
        guard let id = await resolve(target), let group = book.group(containing: id) else { return Self.notGrouped }
        guard let digit else { return .unavailable(reason: L10n.text("tabgroups.press.t.then.a.number")) }
        let index = digit == 0 ? 9 : digit - 1
        guard group.members.indices.contains(index) else { return .unavailable(reason: L10n.text("tabgroups.there.is.no.tab", String(describing: (index + 1)))) }
        return await activate(group.members[index], in: group.id)
    }

    /// 4.2 item 1: the windows sharing the current window's area (or its group's) join it.
    func mergeArea(target: WindowID?) async -> CommandResult {
        guard let id = await resolve(target), let found = await windows.window(id) else {
            return .unavailable(reason: L10n.text("tabgroups.no.focused.window"))
        }
        let anchor = asPlaced(found)
        let existing = book.group(containing: id)
        let reference = existing?.area ?? anchor.frame
        let candidates = await windows.windows().filter { other in
            other.id != id && book.group(containing: other.id) == nil && canGroup(other, with: anchor)
                && TabGeometry.sharesArea(other.frame, reference)
        }.sorted { $0.id < $1.id }
        guard !candidates.isEmpty else { return .unavailable(reason: L10n.text("tabgroups.no.other.windows.in.this.area")) }
        guard let existing else { return await createGroup(active: anchor, others: candidates) }
        for other in candidates { await join(other, into: existing.id, activate: false) }
        scheduleReconcile()
        return .done
    }

    /// Whether `other` may share a group with `anchor`: on screen, on the same display and Space.
    /// `evenHidden` lets a hidden application's window in, for a caller that names its windows
    /// rather than gathering those in view: its tab is faded, another tab shows until the
    /// application is back, and making it the tab in front unhides the application.
    func canGroup(_ other: WindowInfo, with anchor: WindowInfo, evenHidden: Bool = false) -> Bool {
        guard !other.isMinimized, !other.isFullscreen, evenHidden || !isAppHidden(other.pid) else { return false }
        if let display = anchor.displayID, let otherDisplay = other.displayID, display != otherDisplay { return false }
        if !anchor.spaceIDs.isEmpty, !other.spaceIDs.isEmpty, Set(anchor.spaceIDs).isDisjoint(with: other.spaceIDs) {
            return false
        }
        return true
    }

    /// `window` where the layout put it: at the frame it was asked to take, while it is at what it
    /// made of that frame. A window sized in character cells is some points off the place, more
    /// than a snap's few; the place is what a group made from it fills, and what another window
    /// snapped there lands on. A window nobody placed, or moved since, is where it is.
    func asPlaced(_ window: WindowInfo) -> WindowInfo {
        guard let asked = placement(of: window.id, at: window.frame) else { return window }
        var placed = window
        placed.frame = asked.frame
        return placed
    }

    /// `active` and those of `others` that fit become a group; `active` stays in front.
    func createGroup(active: WindowInfo, others: [WindowInfo]) async -> CommandResult {
        // The bar takes the window's own top: the group fills exactly the place the window had.
        let area = active.frame
        let member = TabGeometry.memberFrame(of: area, barHeight: barHeight)
        var fitted: [WindowInfo] = []
        for other in others {
            if await place(other, at: member) { fitted.append(other) }
        }
        guard !fitted.isEmpty else { return .failed(reason: L10n.text("tabgroups.the.other.windows.minimum.sizes.exceed.this")) }
        if !TabGeometry.same(active.frame, member) { await write(active.id, member) }
        let space = active.spaceIDs.count == 1 ? active.spaceIDs.first : nil
        guard let group = book.create(members: [active.id] + fitted.map(\.id), active: active.id, area: area,
                                      displayID: active.displayID, spaceID: space) else {
            return .failed(reason: L10n.text("tabgroups.these.windows.already.belong.to.another.tab"))
        }
        for var info in [active] + fitted {
            info.frame = member
            infos[info.id] = info
        }
        log.note("\(group.id)：\(group.members.count) 个窗口")
        markUsed(group.id)
        return await activate(active.id, in: group.id)
    }

    /// Moves `window` onto `frame`; false, with the window put back, when it cannot take that place
    /// (`TabGeometry.takesPlace`). It goes back where it was, or to `home` when it is owed another
    /// place. A window that takes the place at a size of its own, as one sized in character cells
    /// does, is in: `write` has remembered what it was asked and what it took (`answers`), so the
    /// group goes by the frame written from its first report on.
    func place(_ window: WindowInfo, at frame: CGRect, home: CGRect? = nil) async -> Bool {
        guard case .success(let actual) = await write(window.id, frame) else {
            // Nothing moved, but a window owed another place than where it is still goes there.
            if let home { await write(window.id, home) }
            return false
        }
        guard TabGeometry.takesPlace(actual, of: frame) else {
            log.note("\(window.appName) 放不进 \(frame)，读回 \(actual)")
            refused[window.id] = frame
            await putBack(window.id, to: home ?? window.frame)
            return false
        }
        // It takes the frame now: a refusal remembered for this very frame no longer holds.
        if refused[window.id].map({ TabGeometry.coincides($0, frame) }) == true { refused[window.id] = nil }
        return true
    }

    /// Puts `window` into the group at `index` (appended when nil), out of any group it was in.
    @discardableResult
    func join(_ window: WindowInfo, into groupID: TabGroupID, at index: Int? = nil, activate: Bool) async -> Bool {
        if let current = book.group(containing: window.id) {
            guard current.id != groupID else {
                if let index { book.move(window.id, to: index) }
                showBar(groupID)
                return activate ? await self.activate(window.id, in: groupID) == .done : true
            }
            await leave(window.id)
        }
        guard let group = book.group(groupID) else { return false }
        let member = TabGeometry.memberFrame(of: group.area, barHeight: barHeight)
        guard await place(window, at: member) else { return false }
        book.add(window.id, to: groupID, at: index, activate: false)
        var info = window
        info.frame = member
        infos[window.id] = info
        guard activate else {
            showBar(groupID)
            return true
        }
        return await self.activate(window.id, in: groupID) == .done
    }

    /// 4.2 item 2: the picked window joins the current window's group, or makes one with it.
    func add(picked: WindowInfo?, target: WindowID?) async -> CommandResult {
        guard let picked else { return .done }
        guard let id = await resolve(target), let current = await windows.window(id) else {
            return .unavailable(reason: L10n.text("tabgroups.no.focused.window"))
        }
        let anchor = asPlaced(current)
        guard picked.id != anchor.id else { return .unavailable(reason: L10n.text("tabgroups.the.selected.window.is.already.focused")) }
        if let group = book.group(containing: id) {
            if book.group(containing: picked.id)?.id == group.id { return await activate(picked.id, in: group.id) }
            return await join(picked, into: group.id, activate: true) ? .done
                : .failed(reason: L10n.text("tabgroups.the.window.from.does.not.fit.in", String(describing: (picked.appName))))
        }
        if book.group(containing: picked.id) != nil { await leave(picked.id) }
        guard let fresh = await windows.window(picked.id) else { return .failed(reason: L10n.text("tabgroups.the.selected.window.could.not.be.found")) }
        let result = await createGroup(active: anchor, others: [fresh])
        guard result == .done, let group = book.group(containing: picked.id) else { return result }
        return await activate(picked.id, in: group.id)
    }

    /// 4.7: `id` leaves its group as a window of the whole area's size, nudged down and right.
    func detach(_ id: WindowID) async -> CommandResult {
        guard let group = book.group(containing: id) else { return Self.notGrouped }
        let visible = display(around: group.area)?.visibleFrame ?? group.area
        let frame = TabGeometry.detachedFrame(area: group.area, visible: visible)
        await leave(id)
        await write(id, frame)
        _ = await windows.focus(id)
        return .done
    }

    /// 4.7: every window takes the whole area back, still stacked as they were; the bar goes.
    func ungroup(_ groupID: TabGroupID) async {
        guard let group = book.dissolve(groupID) else { return }
        presenter.hide(groupID)
        forgetPreview(of: groupID)
        for id in group.members {
            infos[id] = nil
            await write(id, group.area)
        }
    }

    // MARK: Merging on snap

    /// 4.2 item 3: a window the user brought to rest exactly on a group or another window joins it.
    /// Where the layout put a window, the place it asked is what counts (`asPlaced`).
    func mergeOnSnap(window id: WindowID) async {
        guard book.group(containing: id) == nil, let read = await windows.window(id), !read.isMinimized,
              !read.isFullscreen else { return }
        let info = asPlaced(read)
        if let group = groupsByUse.first(where: { group in
            TabGeometry.coincides(group.area, info.frame)
                || TabGeometry.coincides(TabGeometry.memberFrame(of: group.area, barHeight: barHeight), info.frame)
        }), !wasRefused(id, in: group) {
            await join(info, into: group.id, activate: true)
            return
        }
        let member = TabGeometry.memberFrame(of: info.frame, barHeight: barHeight)
        let others = await windows.windows().filter { other in
            other.id != id && book.group(containing: other.id) == nil && canGroup(other, with: info)
                && TabGeometry.coincides(asPlaced(other).frame, info.frame)
                && !(refused[other.id].map { TabGeometry.coincides($0, member) } ?? false)
        }.sorted { $0.id < $1.id }
        guard !others.isEmpty else { return }
        log.note("吸附合并：\(id)")
        _ = await createGroup(active: info, others: others)
    }

    /// 4.2 item 3, a group brought to rest: groups and windows exactly on its area join it.
    func mergeOnSnap(group groupID: TabGroupID) async {
        guard let group = book.group(groupID), let active = infos[group.active] else { return }
        for other in book.all where other.id != groupID && isOnScreen(other)
            && TabGeometry.coincides(other.area, group.area) {
            book.absorb(other.id, into: groupID)
            presenter.hide(other.id)
            forgetPreview(of: other.id)
        }
        let member = TabGeometry.memberFrame(of: group.area, barHeight: barHeight)
        let joining = await windows.windows().filter { other in
            let resting = asPlaced(other).frame
            return book.group(containing: other.id) == nil && canGroup(other, with: active) && !wasRefused(other.id, in: group)
                && (TabGeometry.coincides(resting, group.area) || TabGeometry.coincides(resting, member))
        }.sorted { $0.id < $1.id }
        log.trace("\(groupID) 停稳后合并：\(joining.map(\.id.rawValue))")
        for other in joining { await join(other, into: groupID, activate: false) }
        showBar(groupID)
        scheduleReconcile()
    }

    /// Whether `id` already failed to take this group's frame; trying again would only fail again.
    func wasRefused(_ id: WindowID, in group: TabGroup) -> Bool {
        refused[id].map { TabGeometry.coincides($0, TabGeometry.memberFrame(of: group.area, barHeight: barHeight)) } ?? false
    }

    // MARK: ⌘-dragging a window onto a bar

    func handle(_ event: InputEvent) async {
        switch event {
        case .leaderTriggered:
            lastGesture = scheduler.now
        case .mouseDown(let mouse):
            lastGesture = scheduler.now
            // A tab drag still open here never heard its mouse come up.
            cancelTabDrag()
            guard mouse.button == .left, settings.joinsByCommandDrag else { return }
            let pressed = await pressedWindow(at: mouse.location)
            await apply(drag.buttonDown(at: mouse.location, modifiers: mouse.modifiers, window: pressed))
        case .mouseDragged(let mouse):
            guard mouse.button == .left else { return }
            if tabDrag != nil {
                tabDrag?.point = mouse.location
                tabDrag?.command = JoinDragTracker.joins(with: mouse.modifiers)
                refreshTabDrag()
            }
            guard settings.joinsByCommandDrag else { return }
            await apply(drag.pointerMoved(to: mouse.location, modifiers: mouse.modifiers, zones: joinZones()))
        case .mouseUp(let mouse):
            lastGesture = scheduler.now
            guard mouse.button == .left else { return }
            if let tab = tabDrag?.tab {
                log.trace("拖标签 \(tab)：鼠标松开")
                await dropTab(tab, at: mouse.location, command: JoinDragTracker.joins(with: mouse.modifiers))
            }
            guard settings.joinsByCommandDrag else { return }
            await apply(drag.buttonUp(at: mouse.location, modifiers: mouse.modifiers, zones: joinZones()))
        case .modifiersChanged(let modifiers):
            if tabDrag != nil {
                tabDrag?.command = JoinDragTracker.joins(with: modifiers)
                refreshTabDrag()
            }
            guard settings.joinsByCommandDrag else { return }
            await apply(drag.modifiersChanged(modifiers, zones: joinZones()))
        case .shortcut, .mouseMoved, .scroll:
            break
        }
    }

    func pressedWindow(at point: CGPoint) async -> (id: WindowID, frame: CGRect)? {
        guard let id = await windows.windowID(at: point), let info = await windows.window(id) else { return nil }
        return (id, info.frame)
    }

    /// Each bar on screen, a little taller than drawn and short of the display's left and right
    /// edges, where the layout module snaps.
    func joinZones() -> [JoinDragTracker.Zone] {
        groupsByUse.map { group in
            let bar = TabGeometry.barFrame(of: group.area, barHeight: barHeight)
            var zone = bar.insetBy(dx: 0, dy: -Self.zoneSlack)
            if let display = display(around: group.area)?.frame {
                // Short of the layout's edge zones: left, right, and the top one over the menu bar.
                let left = max(zone.minX, display.minX + Self.edgeReach)
                let right = min(zone.maxX, display.maxX - Self.edgeReach)
                let top = max(zone.minY, display.minY + Self.edgeReach + 1)
                zone = CGRect(x: left, y: top, width: max(0, right - left), height: max(0, zone.maxY - top))
            }
            return JoinDragTracker.Zone(group: group.id, frame: zone, bar: bar, slots: group.members.count + 1)
        }
    }

    func apply(_ effects: [JoinDragTracker.Effect]) async {
        for effect in effects {
            switch effect {
            case .pullOut(let id):
                if book.group(containing: id) != nil { await leave(id) }
            case .preview(let id, let target):
                guard book.group(target.group) != nil else {
                    setDropPreview(nil)
                    continue
                }
                if draggedItem?.id != id { draggedItem = await tabItem(forWindow: id) }
                if let tab = draggedItem {
                    setDropPreview(DropPreview(group: target.group, tab: tab, slot: target.index))
                }
            case .clearPreview:
                setDropPreview(nil)
            case .join(let id, let target):
                guard let info = await windows.window(id) else { continue }
                await join(info, into: target.group, at: target.index, activate: true)
            }
        }
    }

    /// Shows what a drag would add in one bar, or in none. A bar something from outside would
    /// join comes in front of the dragged window meanwhile, and goes back above its own window.
    func setDropPreview(_ preview: DropPreview?) {
        guard preview != dropPreview else { return }
        let changed = Set([dropPreview?.group, preview?.group].compactMap { $0 })
        dropPreview = preview
        let joining = preview.flatMap { book.group($0.group)?.members.contains($0.tab.id) == false ? $0.group : nil }
        if let lifted = liftedBar, lifted != joining {
            if let group = book.group(lifted) { reorderBar(lifted, above: group.active) }
            liftedBar = nil
        }
        for id in changed { showBar(id) }
        // Only a bar whose Space shows: the window being dragged is on the Space showing.
        if let joining, liftedBar != joining, book.group(joining).map(isOnScreen) == true {
            presenter.lift(joining)
            liftedBar = joining
        }
    }

    /// The group ended: its preview and its place in front go with it.
    func forgetPreview(of groupID: TabGroupID) {
        if dropPreview?.group == groupID { dropPreview = nil }
        if liftedBar == groupID { liftedBar = nil }
    }

    /// A window that is in no group, as the tab it would become.
    func tabItem(forWindow id: WindowID) async -> TabItem {
        let info = await windows.window(id)
        return TabItem(id: id, title: info?.title ?? "", appName: info?.appName ?? "", pid: info?.pid ?? 0,
                       bundleID: info?.bundleID, isActive: false, isHidden: false)
    }

    // MARK: The bars' controls

    func handle(_ action: TabBarAction) async {
        switch action {
        case .select(let id):
            guard let group = book.group(containing: id) else { return }
            _ = await activate(id, in: group.id)
        case .close(let id):
            if case .failure(let error) = await windows.close(id) { log.problem("关闭 \(id) 失败：\(error)") }
        case .remove(let id):
            _ = await detach(id)
        case .ungroup(let groupID):
            await ungroup(groupID)
        case .drag(let id, let point, let command):
            dragTab(id, to: point, command: command)
        case .drop(let id, let point, let command):
            if tabDrag?.tab == id { log.trace("拖标签 \(id)：标签栏报告松手") }
            await dropTab(id, at: point, command: command)
        }
    }

    /// The chip reports its tab dragged. That starts the drag; from then on mouse events report
    /// it as well. They are what carries it: measured on the Mac, a chip reports once and then
    /// falls silent, because showing the drag redraws the chip and SwiftUI drops the gesture of
    /// a view it rebuilt, without ever ending it. A report that comes after the button is up
    /// belongs to a drag already dropped.
    func dragTab(_ id: WindowID, to point: CGPoint, command: Bool) {
        guard isLeftButtonDown(), book.group(containing: id) != nil else { return }
        if tabDrag?.tab != id { log.trace("拖标签 \(id)：开始\(command ? "（⌘）" : "")") }
        tabDrag = TabDrag(tab: id, point: point, command: command)
        refreshTabDrag()
    }

    /// Shows the drag as it stands: the tab in the slot it would take, in its own bar or, with ⌘,
    /// in the bar under the pointer; with ⌘ and over no bar a small tab follows the pointer and
    /// the tab is faded in its bar.
    func refreshTabDrag() {
        guard let drag = tabDrag else { return }
        guard let group = book.group(containing: drag.tab), let tab = item(drag.tab) else { return cancelTabDrag() }
        let target = tabDragTarget(drag, in: group)
        setDropPreview(target.map { DropPreview(group: $0.group, tab: tab, slot: $0.index) })
        showBar(group.id)
        presenter.showGhost(target == nil ? tab : nil, at: drag.point)
    }

    /// Where the dragged tab would go. Without ⌘ it stays in its own bar, in the slot under the
    /// pointer's x wherever the pointer is. With ⌘ it goes to the bar under the pointer, or nowhere.
    func tabDragTarget(_ drag: TabDrag, in group: TabGroup) -> JoinDragTracker.Target? {
        if drag.command { return tabTarget(at: drag.point, dragging: drag.tab) }
        let bar = TabGeometry.barFrame(of: group.area, barHeight: barHeight)
        let layout = TabBarLayout(barWidth: bar.width, count: group.members.count)
        return JoinDragTracker.Target(group: group.id, index: layout.slot(atX: drag.point.x - bar.minX))
    }

    /// Ends a tab drag without moving anything.
    func cancelTabDrag() {
        guard let drag = tabDrag else { return }
        log.trace("拖标签 \(drag.tab)：取消")
        tabDrag = nil
        setDropPreview(nil)
        presenter.showGhost(nil, at: .zero)
        if let group = book.group(containing: drag.tab) { showBar(group.id) }
    }

    /// 4.3: let go, the tab takes its slot. With ⌘ it may be another bar's, and well away from
    /// every bar the tab becomes a window under the pointer. The chip and the mouse both report
    /// the drop; the second report finds no drag and does nothing.
    func dropTab(_ id: WindowID, at point: CGPoint, command: Bool) async {
        guard tabDrag?.tab == id else { return }
        let drag = TabDrag(tab: id, point: point, command: command)
        tabDrag = nil
        setDropPreview(nil)
        presenter.showGhost(nil, at: point)
        guard let group = book.group(containing: id) else { return }
        showBar(group.id)
        if let target = tabDragTarget(drag, in: group) {
            if target.group == group.id {
                book.move(id, to: target.index)
                showBar(group.id)
            } else if let info = await windows.window(id) {
                await join(info, into: target.group, at: target.index, activate: true)
            }
            return
        }
        let bar = TabGeometry.barFrame(of: group.area, barHeight: barHeight)
        guard !bar.insetBy(dx: -Self.tearDistance, dy: -Self.tearDistance).contains(point) else { return }
        let visible = displays.first { $0.frame.contains(point) }?.visibleFrame
            ?? display(around: group.area)?.visibleFrame ?? group.area
        let frame = TabGeometry.droppedFrame(size: group.area.size, at: point, visible: visible)
        await leave(id)
        await write(id, frame)
        _ = await windows.focus(id)
    }

    /// The bar under `point` and the slot the dragged tab would take there. Its own bar keeps
    /// its number of slots; another bar gains one.
    func tabTarget(at point: CGPoint, dragging id: WindowID) -> JoinDragTracker.Target? {
        for group in groupsByUse {
            let bar = TabGeometry.barFrame(of: group.area, barHeight: barHeight)
            guard bar.insetBy(dx: 0, dy: -Self.zoneSlack).contains(point) else { continue }
            let slots = group.members.count + (group.members.contains(id) ? 0 : 1)
            let layout = TabBarLayout(barWidth: bar.width, count: slots)
            return JoinDragTracker.Target(group: group.id, index: layout.slot(atX: point.x - bar.minX))
        }
        return nil
    }

    func item(_ id: WindowID) -> TabItem? {
        guard let group = book.group(containing: id) else { return nil }
        return content(of: group).tabs.first { $0.id == id }
    }
}
