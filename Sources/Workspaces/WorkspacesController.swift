import Contracts
import CoreKit
import Foundation
import Observation

/// Opening workspaces on desktops of their own, saving and reverting to their checkpoints, and
/// releasing them (workspaces design section 6). The commands, the palette entries, the menu bar
/// and the settings page all go through here.
@MainActor
@Observable
final class WorkspacesController {
    let library: WorkspaceLibrary
    /// The report of the latest expansion, while it runs and after it ends.
    private(set) var lastReport: ExpansionReport?
    /// The open or revert under way.
    private(set) var expansionTask: Task<Void, Never>?
    /// The Space list as last read. Whether a workspace is open is worked out from it and the
    /// library each time, so a change to either shows at once.
    private(set) var desktops: [SpaceInfo] = []
    @ObservationIgnored private var watching: Task<Void, Never>?
    /// The desktop showing on each display as the event loop last saw it, to tell which was left.
    @ObservationIgnored private var showing: [DisplayID: SpaceID] = [:]
    @ObservationIgnored private let autoSaver: CheckpointAutoSaver
    @ObservationIgnored private var desktopReads = 0
    @ObservationIgnored private var expansion: (token: UUID, workspace: UUID)?
    /// Workspace → the entries its last expansion did not deliver. A save nobody asked for keeps
    /// them; a save by hand is exact and ends that. In memory only: empty after a restart.
    @ObservationIgnored private var undelivered: [UUID: Set<UUID>] = [:]
    /// The workspaces whose tab groups are on their desktops as far as they can be since the
    /// module started: restored on arrival, expanded, or saved as new. Their saves take the
    /// groups as the desktop has them. In memory only: empty after a restart.
    @ObservationIgnored private var restored: Set<UUID> = []
    @ObservationIgnored private let log = DiagnosticLog("workspaces")
    /// The open or revert begun last, also once it was abandoned: the next one waits for it.
    @ObservationIgnored private var lastExpansion: Task<Void, Never>?
    /// From `stop()` on nothing writes to the library, whatever is still under way.
    @ObservationIgnored private var isStopped = false
    @ObservationIgnored private let windows: any WindowService
    @ObservationIgnored private let placement: (any PlacementService)?
    @ObservationIgnored private let tabGroups: (any TabGroupService)?
    @ObservationIgnored private let environment: WorkspaceEnvironment

    init(context: ModuleContext, environment: WorkspaceEnvironment) {
        library = WorkspaceLibrary(settings: context.settings, now: environment.now)
        windows = context.windows
        placement = context.placement
        tabGroups = context.tabGroups
        self.environment = environment
        autoSaver = CheckpointAutoSaver(clock: environment.clock)
    }

    var isExpanding: Bool { expansionTask != nil }

    /// Why workspaces cannot be opened or reverted right now, or nil.
    var expansionUnavailableReason: String? {
        if placement == nil { return L10n.text("workspaces.the.layout.module.is.disabled.so.the") }
        if !windows.isAuthorized { return WorkspaceExpander.permissionLost }
        return nil
    }

    /// What is in the way of the workspace's buttons on the settings page.
    func obstacles(for id: UUID) -> WorkspaceObstacles {
        WorkspaceObstacles(permission: windows.isAuthorized ? nil : L10n.text("workspaces.accessibility.access.is.missing.windows.cannot.be.workspacescontroller"),
                           placement: placement == nil ? L10n.text("workspaces.the.layout.module.is.disabled.the.placement") : nil,
                           addingDesktops: windows.unavailableReason(for: .manageSpaces),
                           otherDesktops: windows.unavailableReason(for: .otherSpaceWindows),
                           isExpanding: isExpanding(id))
    }

    /// Whether this workspace is the one being opened or expanded.
    private func isExpanding(_ id: UUID) -> Bool {
        expansionTask != nil && expansion?.workspace == id
    }

    /// Reads the desktops and follows their changes until `stop()`.
    func start() {
        isStopped = false
        library.purgeExpired()
        watching?.cancel()
        // Subscribe before reading, so no change in between is lost.
        let events = windows.events()
        watching = Task { [weak self] in
            await self?.followDesktops()
            for await event in events {
                switch event {
                // The current desktop and the displays are part of what the list says.
                case .spacesChanged, .currentSpaceChanged, .displaysChanged: await self?.followDesktops()
                case .appeared, .disappeared, .moved, .resized, .focused, .minimized, .restored, .titleChanged,
                     .exposeChanged, .appLaunched, .appTerminated, .appHidden, .appUnhidden: break
                }
            }
        }
        scheduleAutoSave()
    }

    /// Whether the workspace is open, and on which desktop.
    func state(of id: UUID) -> WorkspaceDesktops.State {
        guard let workspace = library.workspace(id: id) else { return .closed }
        return WorkspaceDesktops.state(of: workspace, among: library.workspaces, in: desktops)
    }

    /// Reads the Space list. Of two reads under way the later one is kept.
    @discardableResult
    func refreshDesktops() async -> [SpaceInfo] {
        desktopReads += 1
        let read = desktopReads
        let spaces = await windows.spaces()
        if read == desktopReads, spaces != desktops { desktops = spaces }
        return spaces
    }

    /// The desktop showing where the focused window is, else on the main display; nil when the
    /// Space list cannot be read.
    private func currentDesktop(among spaces: [SpaceInfo]) async -> SpaceInfo? {
        async let displays = windows.displays()
        var focusedDisplay: DisplayID?
        if let focused = await windows.focusedWindowID() { focusedDisplay = await windows.window(focused)?.displayID }
        return WorkspaceDesktops.current(displays: await displays, spaces: spaces, focusedDisplay: focusedDisplay)
    }

    /// The workspace that owns the current desktop.
    private func currentWorkspace() async -> Workspace? {
        let spaces = await refreshDesktops()
        guard let desktop = await currentDesktop(among: spaces) else { return nil }
        return WorkspaceDesktops.owner(of: desktop, among: library.workspaces)
    }

    // MARK: Saving

    /// Saves the current desktop (workspaces design 6.2): over the checkpoint of the workspace
    /// that owns it, else as a new workspace that from then on owns it, which `name` is for.
    /// Returns the workspace that took the windows.
    func saveCurrentDesktop(named name: String = "") async -> (result: CommandResult, workspace: UUID?) {
        guard windows.isAuthorized else { return (.unavailable(reason: L10n.text("workspaces.accessibility.access.is.missing.windows.cannot.be.workspacescontroller.2")), nil) }
        let spaces = await refreshDesktops()
        let desktop = await currentDesktop(among: spaces)
        let captured = await WindowCapture.capture(from: windows, tabGroups: tabGroups, desktop: desktop)
        guard !captured.windows.isEmpty else { return (.failed(reason: Self.nothingToSave), nil) }
        guard await dropStaleBindings() else { return (.unavailable(reason: Self.stopped), nil) }
        do {
            if let desktop, let owner = WorkspaceDesktops.owner(of: desktop, among: library.workspaces) {
                if let refusal = refusalToSave(owner) { return (.failed(reason: refusal), nil) }
                let workspace = try library.saveCheckpoint(owner.id, captured: captured, groups: groupsToSave(owner.id))
                autoSaver.noteSaved(workspace.id)
                undelivered[workspace.id] = nil
                environment.notifier.show(message: Self.saved(workspace, from: captured))
                return (.done, workspace.id)
            }
            let workspace = try library.create(windows: captured.windows, focused: captured.focused, name: name,
                                               tabGroups: captured.tabGroups, screenAspect: captured.screenAspect)
            autoSaver.noteSaved(workspace.id)
            // Its groups are the ones just captured: nothing to restore.
            restored.insert(workspace.id)
            var message = desktop.map { L10n.text("workspaces.saved.desktop.as", String(describing: ($0.index)), String(describing: (workspace.name))) } ?? L10n.text("workspaces.saved", String(describing: (workspace.name)))
            message += L10n.text("workspaces.apps.workspacescontroller", String(describing: (workspace.appCount))) + (library.leaderKeys(for: workspace.id).map { L10n.text("workspaces.press.to.open", String(describing: ($0))) } ?? "")
            if let desktop {
                if captured.fromEveryDesktop { message = L10n.text("text.sentence", message, Self.everyDesktop) }
                if let binding = WorkspaceDesktops.binding(for: desktop) {
                    try library.bind(workspace.id, to: binding)
                } else {
                    message = L10n.text("text.sentence", message, WorkspaceLibraryError.unnamedDesktop.message)
                }
            } else {
                message += L10n.text("workspaces.could.not.read.the.desktop.list.no")
            }
            environment.notifier.show(message: message)
            return (.done, workspace.id)
        } catch {
            return (.failed(reason: Self.message(for: error)), nil)
        }
    }

    /// Captures the workspace's own desktop as its checkpoint, which needs the workspace to be
    /// open. Returns a message for the user.
    func saveCheckpoint(_ id: UUID) async -> String {
        guard windows.isAuthorized else { return L10n.text("workspaces.accessibility.access.is.missing.windows.cannot.be.workspacescontroller.2") }
        let spaces = await refreshDesktops()
        guard let workspace = library.workspace(id: id) else { return WorkspaceLibraryError.missingWorkspace.message }
        guard case .open(let desktop) = WorkspaceDesktops.state(of: workspace, among: library.workspaces, in: spaces) else {
            return L10n.text("workspaces.is.not.open.its.checkpoint.was.not", String(describing: (workspace.name)))
        }
        let captured = await WindowCapture.capture(from: windows, tabGroups: tabGroups, desktop: desktop)
        guard !captured.windows.isEmpty else { return Self.nothingToSave }
        guard await dropStaleBindings() else { return Self.stopped }
        if let refusal = refusalToSave(workspace) { return refusal }
        do {
            let saved = try library.saveCheckpoint(id, captured: captured, groups: groupsToSave(id))
            autoSaver.noteSaved(id)
            undelivered[id] = nil
            return Self.saved(saved, from: captured)
        } catch {
            return Self.message(for: error)
        }
    }

    /// Why the user's save of the workspace is refused, or nil: while it is being opened or
    /// expanded, its desktop holds only part of the checkpoint. Asked right before the write.
    private func refusalToSave(_ workspace: Workspace) -> String? {
        isExpanding(workspace.id) ? L10n.text("workspaces.is.expanding.wait.for.it.to.finish", String(describing: (workspace.name))) : nil
    }

    /// What a save makes of the saved tab groups the capture shows nothing of. Once the
    /// workspace's groups were restored the desktop is the truth, and a group the user dissolved
    /// leaves the checkpoint. Before that, as after Tangler restarted and until the desktop is
    /// visited, and without a tab group service, the capture says nothing about them.
    private func groupsToSave(_ id: UUID) -> Checkpoint.Groups {
        tabGroups != nil && restored.contains(id) ? .captured : .keepUnseen
    }

    /// Lets go of the desktops that are gone, before a write. The list is read here, with nothing
    /// awaited between the read and the drop: a list read before a capture or a new desktop
    /// would take a binding made meanwhile for stale. False once the module stopped, when
    /// nothing is to be written at all.
    private func dropStaleBindings() async -> Bool {
        let spaces = await refreshDesktops()
        guard !isStopped else { return false }
        library.dropStaleBindings(spaces: spaces)
        return true
    }

    /// Saves a checkpoint nobody asked for, as before a release, and says nothing. It writes only
    /// what is certain: nothing from a desktop without windows, and nothing when the windows do
    /// not say which desktop they are on, which would take those of every desktop. Nor does it
    /// write once the module stopped, or when an open or revert of the workspace began
    /// meanwhile, and never over a locked workspace, which only the user's own save changes. The
    /// entries the last expansion did not deliver stay in the checkpoint: their windows are
    /// missing because they never came, not because the user closed them. True when saved.
    @discardableResult
    func saveCheckpointQuietly(_ id: UUID, on desktop: SpaceInfo) async -> Bool {
        guard windows.isAuthorized else { return false }
        let captured = await WindowCapture.capture(from: windows, tabGroups: tabGroups, desktop: desktop)
        guard !captured.windows.isEmpty, !captured.fromEveryDesktop else { return false }
        guard !Task.isCancelled, !isStopped, !autoSaver.isSettling(id) else { return false }
        guard library.workspace(id: id)?.isLocked != true else { return false }
        return (try? library.saveCheckpoint(id, captured: captured, keeping: undelivered[id] ?? [],
                                            groups: groupsToSave(id))) != nil
    }

    // MARK: Saving automatically

    /// Whether releasing a workspace saves its checkpoint first: the automatic saving setting.
    var savesOnRelease: Bool { library.autoSave }

    /// Turning it off stops the timer at once.
    func setAutoSave(_ on: Bool) {
        guard on != library.autoSave else { return }
        library.setAutoSave(on)
        scheduleAutoSave()
    }

    /// The interval starts over with the new length.
    func setAutoSaveMinutes(_ minutes: Int) {
        let before = library.autoSaveMinutes
        library.setAutoSaveMinutes(minutes)
        if library.autoSaveMinutes != before { scheduleAutoSave() }
    }

    private var autoSaveInterval: Duration { .seconds(60 * library.autoSaveMinutes) }

    /// The timer runs while the module does and the setting is on.
    private func scheduleAutoSave() {
        guard watching != nil, library.autoSave else { return autoSaver.stopTimer() }
        autoSaver.schedule(every: autoSaveInterval) { [weak self] in await self?.saveShowingWorkspaces() }
    }

    /// Starts a quiet save of the workspace, unless it is settling after an expansion; the save
    /// already under way is returned instead of a second one.
    @discardableResult
    private func autoSave(_ id: UUID, on desktop: SpaceInfo) -> Task<Bool, Never>? {
        autoSaver.save(id) { [weak self] in await self?.saveCheckpointQuietly(id, on: desktop) ?? false }
    }

    /// The automatic saves under way, for tests to wait for.
    var autoSaves: [Task<Bool, Never>] { autoSaver.savesUnderWay }

    /// The open workspaces and their desktops.
    private func openWorkspaces(in spaces: [SpaceInfo]) -> [(id: UUID, desktop: SpaceInfo)] {
        library.workspaces.compactMap { workspace in
            guard case .open(let desktop) = WorkspaceDesktops.state(of: workspace, among: library.workspaces, in: spaces) else {
                return nil
            }
            return (workspace.id, desktop)
        }
    }

    /// The timer's turn. Only a workspace whose desktop is showing is saved: the windows of the
    /// others have not changed since the user left, and leaving saved them. One saved within the
    /// last half interval, as by hand, is skipped, so this does not follow right after.
    private func saveShowingWorkspaces() async {
        let spaces = await refreshDesktops()
        guard watching != nil, library.autoSave, !Task.isCancelled else { return }
        library.dropStaleBindings(spaces: spaces)
        let recent = autoSaveInterval / 2
        let saves = openWorkspaces(in: spaces).filter { $0.desktop.isCurrent && !autoSaver.wasSaved($0.id, within: recent) }
            .compactMap { autoSave($0.id, on: $0.desktop) }
        for save in saves { _ = await save.value }
    }

    /// Reads the desktops for the event loop. A workspace whose desktop stopped showing is saved
    /// if there is time: the save starts at once and is not waited for. The capture asks for the
    /// windows of that desktop, so it is still right after the switch. A workspace whose desktop
    /// is showing gets its tab groups back, the first time.
    private func followDesktops() async {
        let spaces = await refreshDesktops()
        // An empty list is one that could not be read.
        guard watching != nil, !spaces.isEmpty else { return }
        let before = showing
        showing = Dictionary(spaces.filter(\.isCurrent).map { ($0.displayID, $0.id) }, uniquingKeysWith: { first, _ in first })
        for (display, left) in before where library.autoSave && showing[display] != left {
            guard let desktop = spaces.first(where: { $0.id == left }),
                  let owner = WorkspaceDesktops.owner(of: desktop, among: library.workspaces) else { continue }
            autoSave(owner.id, on: desktop)
        }
        for desktop in spaces where desktop.isCurrent {
            guard let owner = WorkspaceDesktops.owner(of: desktop, among: library.workspaces) else { continue }
            await restoreGroups(of: owner.id, on: desktop)
        }
    }

    /// Forms the workspace's saved tab groups again on its desktop, which is showing: the tab
    /// group service starts without groups when Tangler does, and the windows are still there.
    /// Once per workspace since the module started, whatever comes of it, and not while the
    /// workspace is expanded, which forms them itself. A group is formed when every member's
    /// window is still open on the desktop and none of them is in a group. Forming focuses the
    /// tab in front, which is why the desktop has to be the one showing. What fails is only
    /// logged. Without a tab group service or the permission nothing is tried or settled.
    private func restoreGroups(of id: UUID, on desktop: SpaceInfo) async {
        guard let tabGroups, windows.isAuthorized, !restored.contains(id), !isExpanding(id),
              let workspace = library.workspace(id: id) else { return }
        if !workspace.tabGroups.isEmpty {
            let here = await windows.windows().filter { $0.spaceIDs == [desktop.id] }
            let display = await windows.displays().first { $0.id == desktop.displayID }
            var grouped = Set(await tabGroups.groups().flatMap(\.members))
            func window(of entry: UUID) -> WindowID? {
                guard let ref = workspace.windows.first(where: { $0.id == entry })?.lastWindow else { return nil }
                return here.first { $0.id == ref.windowID && $0.pid == ref.pid }?.id
            }
            for group in workspace.tabGroups {
                let members = group.members.compactMap(window)
                guard members.count == group.members.count, members.count >= 2, grouped.isDisjoint(with: members) else { continue }
                guard !Task.isCancelled, !isStopped, !isExpanding(id) else { return }
                guard let display else {
                    log.problem("没有恢复「\(workspace.name)」的标签组：读不到显示器")
                    break
                }
                switch await tabGroups.form(members: members, active: window(of: group.active) ?? members[0],
                                            area: group.unitArea.frame(in: display.visibleFrame)) {
                case .success(let formed): grouped.formUnion(formed.members)
                case .failure(let error): log.problem("没有恢复「\(workspace.name)」的标签组：\(RestoreOutcomeText.reason(error))")
                }
            }
        }
        guard !Task.isCancelled, !isStopped, library.workspace(id: id) != nil else { return }
        restored.insert(id)
    }

    /// Saves every open workspace before the module stops, as when Tangler quits, and waits for
    /// it at most `limit`. What has not been written by then is not written.
    func saveBeforeStopping(within limit: Duration = .seconds(2)) async {
        guard watching != nil, library.autoSave else { return }
        let (finished, signal) = AsyncStream.makeStream(of: Void.self)
        let saving = Task { [weak self] in
            defer { signal.yield() }
            guard let self else { return }
            let spaces = await self.refreshDesktops()
            guard self.watching != nil, !Task.isCancelled else { return }
            let saves = self.openWorkspaces(in: spaces).compactMap { self.autoSave($0.id, on: $0.desktop) }
            for save in saves { _ = await save.value }
        }
        let timeout = Task { [clock = environment.clock] in
            try? await clock.sleep(limit)
            signal.yield()
        }
        for await _ in finished { break }
        saving.cancel()
        timeout.cancel()
    }

    // MARK: Opening and reverting

    /// The digit typed after W; without one, as from the palette, only a sole workspace is
    /// unambiguous.
    func open(digit: Int?) -> CommandResult {
        if let reason = expansionUnavailableReason { return .unavailable(reason: reason) }
        let count = library.workspaces.count
        guard count > 0 else { return .failed(reason: L10n.text("workspaces.no.workspaces.yet.press.w.s.to")) }
        guard let digit else {
            guard count == 1 else { return .failed(reason: L10n.text("workspaces.press.w.and.a.number.or.search")) }
            return open(library.workspaces[0])
        }
        guard let workspace = library.workspace(forDigit: digit) else {
            return .failed(reason: L10n.text("workspaces.workspace.does.not.exist.total", String(describing: (digit == 0 ? 10 : digit)), String(describing: (count))))
        }
        return open(workspace)
    }

    /// Opens the workspace (workspaces design 6.1): on its desktop already only says so, open on
    /// another desktop goes there and moves nothing, not open gets a new desktop of its own with
    /// the checkpoint expanded on it. Returns at once, so leader mode is not held up while
    /// applications launch; what happened goes to the notifier.
    func open(_ workspace: Workspace) -> CommandResult {
        begin(workspace.id, reverting: false)
    }

    /// Expands the checkpoint on the workspace's desktop (workspaces design 6.3); a workspace that
    /// is not open is opened. Returns at once, like `open`.
    func revert(_ workspace: Workspace) -> CommandResult {
        begin(workspace.id, reverting: true)
    }

    func revertCurrentDesktop() async -> CommandResult {
        if let reason = expansionUnavailableReason { return .unavailable(reason: reason) }
        guard let owner = await currentWorkspace() else { return .failed(reason: Self.noWorkspaceHere) }
        return revert(owner)
    }

    /// One at a time: an open or revert still running is cancelled, and this one waits until it
    /// is over before it begins, since the service refuses a desktop operation while another
    /// runs. Asking again for the workspace that is being opened or expanded leaves it running.
    private func begin(_ id: UUID, reverting: Bool) -> CommandResult {
        if let reason = expansionUnavailableReason { return .unavailable(reason: reason) }
        guard let placement else { return .unavailable(reason: L10n.text("workspaces.the.placement.service.is.unavailable")) }
        if isExpanding(id), let name = library.workspace(id: id)?.name {
            environment.notifier.show(message: L10n.text("workspaces.is.expanding", String(describing: (name))))
            return .done
        }
        let previous = lastExpansion
        previous?.cancel()
        let token = UUID()
        expansion = (token, id)
        let task = Task { [weak self] in
            await previous?.value
            await self?.run(id, reverting: reverting, placement: placement, token: token)
            guard let self, self.expansion?.token == token else { return }
            self.expansionTask = nil
            self.expansion = nil
        }
        expansionTask = task
        lastExpansion = task
        return .done
    }

    private func run(_ id: UUID, reverting: Bool, placement: any PlacementService, token: UUID) async {
        let spaces = await refreshDesktops()
        guard !Task.isCancelled else { return }
        guard let workspace = library.workspace(id: id) else {
            return say(WorkspaceLibraryError.missingWorkspace.message, for: token)
        }
        switch WorkspaceDesktops.state(of: workspace, among: library.workspaces, in: spaces) {
        case .open(let desktop):
            if reverting, workspace.windows.isEmpty {
                say(L10n.text("workspaces.has.no.checkpoint.arrange.the.windows.then", String(describing: (workspace.name))), for: token)
            } else if reverting {
                await expand(workspace, on: desktop.id, placement: placement, token: token)
            } else {
                await goTo(desktop, of: workspace, among: spaces, token: token)
            }
        case .closed:
            await openOnANewDesktop(workspace, among: spaces, placement: placement, token: token)
        }
    }

    /// The workspace is open: its windows stay as they are.
    private func goTo(_ desktop: SpaceInfo, of workspace: Workspace, among spaces: [SpaceInfo], token: UUID) async {
        if await currentDesktop(among: spaces)?.id == desktop.id {
            return say(L10n.text("workspaces.already.in", String(describing: (workspace.name))), for: token)
        }
        let preferred = await ownWindow(of: workspace, on: desktop.id)
        guard !Task.isCancelled else { return }
        if case .failure(let error) = await windows.switchTo(space: desktop.id, focusing: preferred) {
            say(L10n.text("workspaces.could.not.switch.to.the.desktop.for", String(describing: (workspace.name)), String(describing: (RestoreOutcomeText.reason(error)))), for: token)
        }
    }

    /// A window the workspace last used that is on its desktop, for the switch to focus: that of
    /// the entry chosen for the focus, else of the first entry that has one.
    private func ownWindow(of workspace: Workspace, on desktop: SpaceID) async -> WindowID? {
        let open = await windows.windows()
        func window(of entry: SavedWindow) -> WindowID? {
            guard let ref = entry.lastWindow else { return nil }
            return open.first { $0.id == ref.windowID && $0.pid == ref.pid && $0.spaceIDs.contains(desktop) }?.id
        }
        let chosen = workspace.windows.first { $0.id == workspace.options.focusedWindow }
        return chosen.flatMap(window) ?? workspace.windows.lazy.compactMap(window).first
    }

    private func openOnANewDesktop(_ workspace: Workspace, among spaces: [SpaceInfo], placement: any PlacementService,
                                   token: UUID) async {
        var display = await currentDesktop(among: spaces)?.displayID
        if display == nil {
            let displays = await windows.displays()
            display = (displays.first(where: \.isMain) ?? displays.first)?.id
        }
        guard let display else { return say(L10n.text("workspaces.could.not.read.the.display.list.to", String(describing: (workspace.name))), for: token) }
        guard !Task.isCancelled else { return }
        let desktop: SpaceInfo
        switch await windows.addSpace(on: display, switching: true) {
        case .failure(let error):
            return say(L10n.text("workspaces.could.not.open", String(describing: (workspace.name)), String(describing: (RestoreOutcomeText.reason(error)))), for: token)
        case .success(let created):
            desktop = created
        }
        // The desktops as they are now, the new one among them. An open that outlived the module
        // writes nothing.
        guard await dropStaleBindings() else { return }
        guard library.workspace(id: workspace.id) != nil else {
            return environment.notifier.show(message: L10n.text("workspaces.deleted.the.newly.created.desktop.was.kept", String(describing: (workspace.name))))
        }
        // Bound before anything else, so nothing that fails later leaves a desktop nobody owns.
        // This holds for an open that was cancelled meanwhile too.
        guard let binding = WorkspaceDesktops.binding(for: desktop) else {
            return say(L10n.text("workspaces.created.desktop.for", String(describing: (workspace.name)), String(describing: (desktop.index))) + WorkspaceLibraryError.unnamedDesktop.message, for: token)
        }
        do {
            try library.bind(workspace.id, to: binding)
        } catch {
            return say(Self.message(for: error), for: token)
        }
        // Until an expansion says otherwise, no entry has its window on the new desktop.
        undelivered[workspace.id] = Set(workspace.windows.map(\.id))
        // Said whoever cancelled it: another open has taken over the token by now.
        guard !Task.isCancelled else {
            let rest = workspace.windows.isEmpty ? "" : L10n.text("workspaces.expansion.was.cancelled.go.to.that.desktop")
            return environment.notifier.show(message: L10n.text("workspaces.the.desktop.for.is.ready", String(describing: (workspace.name))) + rest)
        }
        // When the new desktop is not showing, the switch is tried once more. If it still is not,
        // nothing is expanded: applications would open their windows on the desktop in front.
        // The binding stays, so W R on that desktop does the rest.
        var reached = desktop
        if !desktop.isCurrent {
            _ = await windows.switchTo(space: desktop.id, focusing: nil)
            reached = await refreshDesktops().first { $0.id == desktop.id } ?? desktop
        }
        guard reached.isCurrent else {
            // The number is the one Mission Control shows.
            let rest = workspace.windows.isEmpty ? "" : L10n.text("workspaces.switch.to.desktop.and.press.w.r", String(describing: (reached.index)))
            return say(L10n.text("workspaces.created.desktop.for.but.could.not.switch", String(describing: (workspace.name)), String(describing: (reached.index))) + rest, for: token)
        }
        guard workspace.windows.isEmpty else {
            return await expand(workspace, on: desktop.id, placement: placement, token: token)
        }
        say(L10n.text("workspaces.opened.arrange.the.windows.then.press.w", String(describing: (workspace.name))), for: token)
    }

    private func expand(_ workspace: Workspace, on desktop: SpaceID, placement: any PlacementService, token: UUID) async {
        // No automatic save takes a desktop that is only partly expanded.
        autoSaver.expansionBegan(workspace.id)
        let expander = WorkspaceExpander(windows: windows, placement: placement, tabGroups: tabGroups,
                                         opener: environment.opener, library: library, timing: environment.timing)
        let report = await expander.expand(workspace, on: desktop, isVoid: { self.isStopped }) { report in
            guard self.expansion?.token == token else { return }
            self.lastReport = report
            self.environment.notifier.show(report)
        }
        autoSaver.expansionEnded(workspace.id)
        // Also after a cancel, and when the desktop was never reached: nothing more came.
        undelivered[workspace.id] = Set(report.entries.filter { !$0.state.hasWindow }.map(\.id))
        // The groups were formed as far as they could be, and the report said which were not.
        if !isStopped { restored.insert(workspace.id) }
        if library.workspace(id: workspace.id) == nil { forget(workspace.id) }
    }

    /// Not once another open or revert has taken over, or the module has stopped.
    private func say(_ message: String, for token: UUID) {
        guard expansion?.token == token else { return }
        environment.notifier.show(message: message)
    }

    func cancelExpansion() {
        expansionTask?.cancel()
    }

    // MARK: Releasing and deleting

    func releaseCurrentDesktop(removingDesktop: Bool = false) async -> CommandResult {
        guard let owner = await currentWorkspace() else { return .failed(reason: Self.noWorkspaceHere) }
        return await release(owner.id, removingDesktop: removingDesktop)
    }

    /// Cuts the workspace loose from its desktop, which stays as an ordinary desktop with its
    /// windows and applications as they are. The checkpoint is saved first when checkpoints are
    /// saved automatically, though not from a desktop still settling after an open or revert.
    /// With `removingDesktop` the desktop is then removed; when that fails, the release stands
    /// and the reason is shown. Without `desktopStays`, as when the caller removes the desktop
    /// itself, the message does not promise that it stays.
    func release(_ id: UUID, removingDesktop: Bool = false, desktopStays: Bool = true) async -> CommandResult {
        let spaces = await refreshDesktops()
        guard let workspace = library.workspace(id: id) else {
            return .failed(reason: WorkspaceLibraryError.missingWorkspace.message)
        }
        guard case .open(let desktop) = WorkspaceDesktops.state(of: workspace, among: library.workspaces, in: spaces) else {
            return .failed(reason: L10n.text("workspaces.is.not.open", String(describing: (workspace.name))))
        }
        abandonExpansion(of: id)
        library.dropStaleBindings(spaces: spaces)
        if savesOnRelease { _ = await autoSave(id, on: desktop)?.value }
        guard !isStopped else { return .unavailable(reason: Self.stopped) }
        do {
            try library.unbind(id)
        } catch {
            return .failed(reason: Self.message(for: error))
        }
        guard removingDesktop else {
            environment.notifier.show(message: L10n.text("workspaces.released", String(describing: (workspace.name))) + (desktopStays ? L10n.text("workspaces.its.desktop.was.kept.as.a.regular") : ""))
            return .done
        }
        switch await windows.removeSpace(desktop.id) {
        case .success:
            environment.notifier.show(message: L10n.text("workspaces.released.and.removed.its.desktop", String(describing: (workspace.name))))
        case .failure(let error):
            environment.notifier.show(message: L10n.text("workspaces.released.but.could.not.remove.its.desktop", String(describing: (workspace.name)), String(describing: (RestoreOutcomeText.reason(error)))))
        }
        await refreshDesktops()
        return .done
    }

    /// Moves the record to the recycle bin (workspaces design 6.5), released: its desktop stays as
    /// an ordinary desktop with its windows. The report of its expansion, when one was running,
    /// is taken off the screen.
    func delete(_ id: UUID) {
        if abandonExpansion(of: id) { environment.notifier.hide() }
        library.moveToBin(id)
        forget(id)
    }

    /// Drops what is remembered about a workspace that is gone.
    private func forget(_ id: UUID) {
        undelivered[id] = nil
        restored.remove(id)
        autoSaver.forget(id)
    }

    /// Ends the open or revert of this workspace; what it would still report is dropped. True
    /// when there was one.
    @discardableResult
    private func abandonExpansion(of id: UUID) -> Bool {
        guard expansion?.workspace == id else { return false }
        expansionTask?.cancel()
        expansionTask = nil
        expansion = nil
        if lastReport?.workspaceID == id, lastReport?.isFinished == false { lastReport = nil }
        return true
    }

    /// Shows why a command did not run. Leader mode closes right after a command, so without
    /// this a refused W 5 would pass silently.
    @discardableResult
    func announce(_ result: CommandResult) -> CommandResult {
        switch result {
        case .done: break
        case .unavailable(let reason), .failed(let reason): environment.notifier.show(message: reason)
        }
        return result
    }

    func stop() {
        isStopped = true
        watching?.cancel()
        watching = nil
        showing = [:]
        restored = []
        autoSaver.stop()
        expansionTask?.cancel()
        expansionTask = nil
        expansion = nil
        environment.notifier.hide()
    }

    static var nothingToSave: String { L10n.text("workspaces.there.are.no.windows.on.this.desktop") }

    /// Said when a desktop's capture had to take the windows of every desktop.
    static var everyDesktop: String { L10n.text("workspaces.window.desktop.membership.is.unavailable.captured.windows") }

    static var noWorkspaceHere: String { L10n.text("workspaces.the.current.desktop.does.not.belong.to") }

    static var stopped: String { L10n.text("workspaces.the.workspace.module.has.stopped") }

    private static func saved(_ workspace: Workspace, from captured: WindowCapture.Result) -> String {
        let message = L10n.text("workspaces.saved.the.checkpoint.for.apps", workspace.name, String(workspace.appCount))
        return captured.fromEveryDesktop ? L10n.text("text.sentence", message, everyDesktop) : message
    }

    static func message(for error: any Error) -> String {
        (error as? WorkspaceLibraryError)?.message ?? error.localizedDescription
    }
}

extension WorkspacesController: DesktopOwnership {
    /// Another module, as the layout module's D X, is about to remove the desktop: the workspace
    /// that owns it is released as by W X, and the desktop is left to the caller.
    func desktopWillBeRemoved(_ space: SpaceID) async {
        let spaces = await refreshDesktops()
        guard !isStopped, let desktop = spaces.first(where: { $0.id == space }),
              let owner = WorkspaceDesktops.owner(of: desktop, among: library.workspaces) else { return }
        _ = await release(owner.id, desktopStays: false)
    }
}
