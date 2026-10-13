import CoreKit
import Contracts
import Foundation

/// Expands a checkpoint on a desktop (workspaces design section 5): goes there, gets every entry
/// its window as `ExpansionPlanner` decides, places the windows, forms the saved tab groups and
/// records which window each entry got. Windows that are not in the checkpoint are never touched.
@MainActor
final class WorkspaceExpander {
    private let windows: any WindowService
    private let placement: any PlacementService
    private let tabGroups: (any TabGroupService)?
    private let opener: any ApplicationOpening
    private let library: WorkspaceLibrary
    private let timing: RestoreTiming

    /// Said when the Accessibility permission is missing at the start or taken away on the way.
    static var permissionLost: String { L10n.text("workspaces.expansion.stopped.because.accessibility.access.was.revoked") }

    init(windows: any WindowService, placement: any PlacementService, tabGroups: (any TabGroupService)?,
         opener: any ApplicationOpening, library: WorkspaceLibrary, timing: RestoreTiming = RestoreTiming()) {
        self.windows = windows
        self.placement = placement
        self.tabGroups = tabGroups
        self.opener = opener
        self.library = library
        self.timing = timing
    }

    /// Calls `progress` whenever the report changes. When the task is cancelled, nothing more is
    /// opened, launched, grouped or focused; the windows obtained by then still go to their saved
    /// frames, and the entries not settled yet are reported as cancelled. The same when the
    /// Accessibility permission is taken away on the way. While `isVoid` answers true, as once
    /// the module has stopped, the windows the entries got are not recorded in the library.
    func expand(_ workspace: Workspace, on desktop: SpaceID, isVoid: () -> Bool = { false },
                progress: (ExpansionReport) -> Void = { _ in }) async -> ExpansionReport {
        let run = ExpansionRun(workspace, target: desktop)
        if let reason = await arrive(run) {
            run.report.notice = reason
        } else {
            await obtainWindows(run, progress: progress)
            await place(run)
            await focusChosenWindow(run)
            await recordWindows(run, unless: isVoid)
        }
        for index in run.entries.indices where run.isWaiting(index) { run.report.entries[index].state = .cancelled }
        run.report.isFinished = true
        progress(run.report)
        return run.report
    }

    /// Applications open their windows on the current desktop, so that must be the target. Returns
    /// why it is not, in which case nothing is opened.
    private func arrive(_ run: ExpansionRun) async -> String? {
        guard windows.isAuthorized else { return Self.permissionLost }
        guard let target = await windows.spaces().first(where: { $0.id == run.target }) else { return L10n.text("workspaces.the.target.desktop.no.longer.exists") }
        run.displayID = target.displayID
        guard !target.isCurrent, !Task.isCancelled else { return nil }
        let chosen = run.workspace.options.focusedWindow.flatMap(run.index(of:))
        let preferred = chosen.flatMap { run.entries[$0].lastWindow?.windowID }
        if case .failure(let error) = await windows.switchTo(space: run.target, focusing: preferred) {
            return L10n.text("workspaces.could.not.switch.to.the.target.desktop", String(describing: (RestoreOutcomeText.reason(error))))
        }
        return nil
    }

    /// One entry at a time, each decided on the windows as they are then: what an earlier entry
    /// opened or launched changes what the next one of the same application needs.
    private func obtainWindows(_ run: ExpansionRun, progress: (ExpansionReport) -> Void) async {
        while !Task.isCancelled {
            // Without the permission no window can be read or asked for: nothing more is opened.
            guard windows.isAuthorized else {
                run.report.notice = Self.permissionLost
                return
            }
            let open = await windows.windows()
            let running = Set(run.entries.compactMap(\.bundleID).filter { opener.isRunning(bundleID: $0) })
            let situation = ExpansionPlanner.Situation(windows: open, target: run.target, running: running,
                                                       canOpenNewWindow: run.menus, options: run.workspace.options)
            let plan = ExpansionPlanner.plan(run.entries, in: situation, settled: run.obtained)
            // Windows that are here already cost nothing, so every entry that has one is settled.
            for index in run.entries.indices where run.isWaiting(index) {
                if case .place(let id) = plan[index].action { run.settle(index, with: id, as: .alreadyHere, note: plan[index].note) }
            }
            progress(run.report)
            guard let index = run.entries.indices.first(where: run.isWaiting) else { return }
            if await readMenus(for: index, in: run, open: open) { continue }
            guard !Task.isCancelled else { return }
            await carryOut(plan[index], for: index, in: run, open: open)
            progress(run.report)
        }
    }

    /// Asks whether the entry's application has a "new window" item, when the plan depends on it:
    /// up to three times a poll apart, since a busy application does not answer, and once per
    /// entry. True when the answer is new, so the entry must be decided again.
    private func readMenus(for index: Int, in run: ExpansionRun, open: [WindowInfo]) async -> Bool {
        let entry = run.entries[index]
        // The contents count as the planner counts them: none while they are not to be opened.
        let contents = run.workspace.options.reopensMissingWindows ? entry.contents : []
        let decides = entry.windowing == .automatic && contents.isEmpty
            || entry.windowing != .onlyWindow && contents.contains { $0.kind == .webPage }
        guard decides, let bundle = entry.bundleID.nonEmpty, run.menus[bundle] == nil, !run.asked.contains(index),
              let pid = pid(of: bundle, among: open) else { return false }
        run.asked.insert(index)
        for attempt in 1...3 {
            if let answer = await windows.canOpenNewWindow(pid: pid) {
                run.menus[bundle] = answer
                return true
            }
            guard attempt < 3, (try? await timing.sleep(timing.pollInterval)) != nil else { break }
        }
        return false
    }

    private func carryOut(_ step: ExpansionStep, for index: Int, in run: ExpansionRun, open: [WindowInfo]) async {
        switch step.action {
        case .place(let id):
            run.settle(index, with: id, as: .alreadyHere, note: step.note)
        case .move(let id):
            switch await windows.move(id, toSpace: run.target) {
            case .success: run.settle(index, with: id, as: .moved, note: step.note)
            case .failure(let error): run.fail(index, as: .notMoved, note: RestoreOutcomeText.reason(error))
            }
        case .launch(let request):
            await launch(request, for: index, in: run, open: open)
        case .open(let way):
            await openWindow(way, for: index, in: run, open: open)
        case .fail(.notRunning):
            run.fail(index, as: .notRunning, note: step.note)
        case .fail(.contentsNotOpened):
            run.fail(index, as: .contentsNotOpened, note: step.note)
        case .fail(.noWindow):
            run.fail(index, as: .noNewWindow, note: step.note)
        }
        // What the planner said of a window that was yet to be opened, as that its contents are not.
        if let note = step.note, step.window == nil, run.obtained[index] != nil { run.addNote(index, note) }
    }

    /// Whether a window may still be opened: not after a cancel, which leaves the entry waiting,
    /// and not once the user has left the target desktop, where the window would not open.
    private func mayOpen(for index: Int, in run: ExpansionRun) async -> Bool {
        guard !Task.isCancelled else { return false }
        guard await hasLeft(run) else { return true }
        run.report.notice = L10n.text("workspaces.you.left.this.desktop.no.more.windows")
        run.fail(index, as: .noNewWindow, note: L10n.text("workspaces.you.have.left.this.desktop"))
        return false
    }

    /// Whether the user has switched to another desktop, read anew until it is so.
    private func hasLeft(_ run: ExpansionRun) async -> Bool {
        if !run.hasLeft {
            run.hasLeft = await windows.spaces().first { $0.id == run.target }?.isCurrent != true
        }
        return run.hasLeft
    }

    private func launch(_ request: OpenRequest, for index: Int, in run: ExpansionRun, open: [WindowInfo]) async {
        guard await mayOpen(for: index, in: run) else { return }
        let before = Set(open.filter { $0.bundleID == request.bundleID }.map(\.id))
        let outcome = await opener.open(request)
        guard !Task.isCancelled else { return }
        guard outcome == .opened else {
            return run.fail(index, as: .noNewWindow, note: RestoreOutcomeText.failure(outcome, launching: true))
        }
        // An application that brings back several windows gets a moment to show the entry's own.
        if let new = await newWindow(for: index, in: run, before: before, polls: timing.pollsAtEnd,
                                     settling: timing.pollsAfterOpen) {
            await take(new.id, for: index, as: .launched, note: new.note, in: run)
        } else if !Task.isCancelled {
            run.fail(index, as: .timedOut, note: nil)
        }
    }

    private func openWindow(_ way: ExpansionStep.NewWindow, for index: Int, in run: ExpansionRun,
                            open: [WindowInfo]) async {
        guard await mayOpen(for: index, in: run) else { return }
        let entry = run.entries[index]
        let own = open.filter { $0.bundleID == entry.bundleID }
        switch way {
        case .contents(let request):
            let outcome = await opener.open(request)
            guard !Task.isCancelled else { return }
            guard outcome == .opened else {
                return run.fail(index, as: .noNewWindow, note: RestoreOutcomeText.failure(outcome, launching: false))
            }
            if let new = await newWindow(for: index, in: run, before: Set(own.map(\.id)),
                                         polls: timing.pollsForNewWindow, settling: 0) {
                await take(new.id, for: index, as: .opened, note: new.note, in: run)
            } else if Task.isCancelled {
                return
            } else if let showing = await windowShowing(entry, in: run) {
                await take(showing, for: index, as: .opened, note: L10n.text("workspaces.contents.appeared.in.an.existing.app.window"), in: run)
            } else {
                run.fail(index, as: .timedOut, note: nil)
            }
        case .menu, .menuThenContents:
            guard let pid = entry.bundleID.flatMap({ pid(of: $0, among: open) }) else {
                return run.fail(index, as: .noNewWindow, note: L10n.text("workspaces.the.app.s.process.could.not.be"))
            }
            switch await windows.openNewWindow(pid: pid) {
            case .failure(let error):
                guard !Task.isCancelled else { return }
                run.fail(index, as: .noNewWindow, note: RestoreOutcomeText.reason(error))
            case .success(let id):
                var note: String?
                // The window in front is the new one, which is where a browser shows the page.
                if case .menuThenContents(let request) = way {
                    let outcome = Task.isCancelled ? OpenOutcome.cancelled : await opener.open(request)
                    if outcome != .opened { note = L10n.text("workspaces.could.not.open.contents", String(describing: (RestoreOutcomeText.failure(outcome, launching: false)))) }
                }
                await take(id, for: index, as: .opened, note: note, in: run)
            }
        }
    }

    /// The application's process: that of one of its windows, else as the system tells, which is
    /// the only way to a running application without windows.
    private func pid(of bundle: String, among open: [WindowInfo]) -> Int32? {
        open.first { $0.bundleID == bundle }?.pid ?? opener.pid(bundleID: bundle)
    }

    /// The window that came for the entry's request: one of its application that the service did
    /// not list before and no entry has. It is never told by the document it reports. Of several,
    /// the one rule 1 pairs with the entry, else the first listed once `settling` more polls have
    /// passed. Nil when none came within `polls`, or on a cancel.
    private func newWindow(for index: Int, in run: ExpansionRun, before: Set<WindowID>, polls: Int,
                           settling: Int) async -> (id: WindowID, note: String?)? {
        let entry = run.entries[index]
        var waited = 0
        var settled = 0
        while !Task.isCancelled {
            let fresh = await windows.windows().filter { window in
                window.bundleID == entry.bundleID && !before.contains(window.id) && !run.obtained.values.contains(window.id)
            }
            let identities = fresh.map(WindowIdentity.init)
            if let first = fresh.first {
                if let exact = WindowMatcher.match([entry], with: identities, allowsSoleRemainder: false,
                                                   contentsMustAgree: false)[0] { return (exact, nil) }
                if settled >= settling {
                    let paired = WindowMatcher.match([entry], with: identities, contentsMustAgree: false)[0]
                    return paired.map { ($0, nil) } ?? (first.id, L10n.text("workspaces.matched.by.application"))
                }
                settled += 1
            } else {
                guard waited < polls else { return nil }
                waited += 1
            }
            do { try await timing.sleep(timing.pollInterval) } catch { return nil }
        }
        return nil
    }

    /// A window that shows the entry's file or folder although no new one came, as when the
    /// application brought an existing window forward for it. Never for web pages, and never a
    /// minimized or full-screen window, which is not brought over.
    private func windowShowing(_ entry: SavedWindow, in run: ExpansionRun) async -> WindowID? {
        guard !entry.contents.contains(where: { $0.kind == .webPage }), let document = entry.documentIdentity else { return nil }
        return await windows.windows().first { window in
            window.bundleID == entry.bundleID && !run.obtained.values.contains(window.id)
                && !window.isMinimized && !window.isFullscreen && WindowIdentity(window).documentURL == document
        }?.id
    }

    /// Gives the entry its window, moving it here first when it opened on another desktop.
    private func take(_ id: WindowID, for index: Int, as state: ExpansionReport.State, note: String?,
                      in run: ExpansionRun) async {
        run.settle(index, with: id, as: state, note: note)
        if let spaces = await windows.window(id)?.spaceIDs, !spaces.isEmpty, !spaces.contains(run.target),
           case .failure(let error) = await windows.move(id, toSpace: run.target) {
            run.addNote(index, L10n.text("workspaces.the.window.opened.on.another.desktop.and", String(describing: (RestoreOutcomeText.reason(error)))))
        }
    }

    /// Tab groups first, through their service; then everyone else, and the members of groups that
    /// were not formed, at their own frames on the target desktop's display. Forming a group
    /// focuses its tab in front, which takes the screen to the target desktop: so none is formed
    /// once the user has left or after a cancel, when every window obtained is placed by itself.
    private func place(_ run: ExpansionRun) async {
        guard !run.obtained.isEmpty else { return }
        let display = await windows.displays().first { $0.id == run.displayID }
        var grouped: Set<Int> = []
        for group in run.workspace.tabGroups {
            let members = group.members.compactMap(run.index(of:)).filter { run.obtained[$0] != nil }
            let ids = members.compactMap { run.obtained[$0] }
            guard let first = ids.first else { continue }
            let reason: String
            if ids.count < 2 {
                reason = L10n.text("workspaces.only.one.tab.group.window.arrived.placed")
            } else if let tabGroups, let display {
                let left = await hasLeft(run)
                guard !Task.isCancelled else { break }
                if left {
                    reason = L10n.text("workspaces.you.left.this.desktop.windows.were.placed")
                } else {
                    let active = run.index(of: group.active).flatMap { run.obtained[$0] } ?? first
                    switch await tabGroups.form(members: ids, active: active, area: group.unitArea.frame(in: display.visibleFrame)) {
                    case .success(let formed):
                        for index in members {
                            if let id = run.obtained[index], formed.members.contains(id) {
                                grouped.insert(index)
                            } else {
                                run.addNote(index, L10n.text("workspaces.could.not.join.the.tab.group.placed"))
                            }
                        }
                        continue
                    case .failure(let error):
                        reason = L10n.text("workspaces.could.not.form.the.tab.group.placed", String(describing: (RestoreOutcomeText.reason(error))))
                    }
                }
            } else {
                reason = tabGroups == nil ? L10n.text("workspaces.the.tab.group.module.is.disabled.windows") : L10n.text("workspaces.could.not.read.the.display.list.or")
            }
            for index in members { run.addNote(index, reason) }
        }
        let alone = run.obtained.keys.sorted().filter { !grouped.contains($0) }
        guard !alone.isEmpty else { return }
        let outcomes = await placement.apply(alone.compactMap { index in
            let entry = run.entries[index]
            return run.obtained[index].map { id in
                Placement(windowID: id, displayID: run.displayID ?? entry.displayID, spaceID: nil,
                          unitFrame: entry.unitFrame, absoluteFrame: entry.frame)
            }
        })
        for index in alone {
            switch run.obtained[index].flatMap({ outcomes[$0] }) {
            case .placed?: break
            case .placedOnFallbackDisplay?: run.addNote(index, L10n.text("workspaces.the.saved.display.is.unavailable.placed.on"))
            case .windowMissing?: run.addNote(index, L10n.text("workspaces.the.window.closed.before.placement"))
            case .failed(let error)?: run.addNote(index, L10n.text("workspaces.could.not.place.the.window", String(describing: (RestoreOutcomeText.text(for: error)))))
            case nil: run.addNote(index, L10n.text("workspaces.the.placement.service.returned.no.result"))
            }
        }
    }

    /// Not after a cancel, and not once the user has left: focusing would take the screen back to
    /// the target desktop.
    private func focusChosenWindow(_ run: ExpansionRun) async {
        guard let chosen = run.workspace.options.focusedWindow, let index = run.index(of: chosen),
              let id = run.obtained[index], !Task.isCancelled else { return }
        let left = await hasLeft(run)
        guard !left, !Task.isCancelled else { return }
        _ = await windows.focus(id)
    }

    private func recordWindows(_ run: ExpansionRun, unless isVoid: () -> Bool) async {
        var refs: [UUID: WindowRef] = [:]
        for (index, id) in run.obtained {
            guard let window = await windows.window(id) else { continue }
            refs[run.entries[index].id] = WindowRef(windowID: id, pid: window.pid)
        }
        guard !isVoid() else { return }
        library.recordWindows(refs, in: run.workspace.id)
    }
}

/// The state of one expansion.
@MainActor
private final class ExpansionRun {
    let workspace: Workspace
    let target: SpaceID
    var report: ExpansionReport
    /// The target desktop's display, known once the desktop was found.
    var displayID: DisplayID?
    /// Entry index → the window it got.
    var obtained: [Int: WindowID] = [:]
    /// Bundle ID → whether the application has a "new window" item, once it answered.
    var menus: [String: Bool] = [:]
    /// The entries whose application was asked for its menus.
    var asked: Set<Int> = []
    /// The user switched to another desktop on the way.
    var hasLeft = false

    init(_ workspace: Workspace, target: SpaceID) {
        self.workspace = workspace
        self.target = target
        report = ExpansionReport(workspace: workspace)
    }

    var entries: [SavedWindow] { workspace.windows }

    func isWaiting(_ index: Int) -> Bool { report.entries[index].state == .waiting }

    func index(of entry: UUID) -> Int? { entries.firstIndex { $0.id == entry } }

    func settle(_ index: Int, with id: WindowID, as state: ExpansionReport.State, note: String?) {
        obtained[index] = id
        report.entries[index].state = state
        report.entries[index].note = note
    }

    func fail(_ index: Int, as state: ExpansionReport.State, note: String?) {
        report.entries[index].state = state
        report.entries[index].note = note
    }

    func addNote(_ index: Int, _ text: String) {
        report.entries[index].note = report.entries[index].note.map { $0 + L10n.text("text.reasonSeparator") + text } ?? text
    }
}
