import CoreKit
import Contracts
import Foundation

/// What expanding does for one entry of a checkpoint (workspaces design 5.2).
struct ExpansionStep: Equatable {
    enum Action: Equatable {
        /// A window that is on the target desktop already.
        case place(WindowID)
        /// A window on another desktop, brought to the target.
        case move(WindowID)
        /// The application is not running.
        case launch(OpenRequest)
        case open(NewWindow)
        case fail(Failure)
    }

    /// How a running application is asked for another window, as measured on the device (design
    /// section 14): Finder shows a folder in a window of its own, a browser shows a page in the
    /// window in front.
    enum NewWindow: Equatable {
        /// Its "new window" menu item.
        case menu
        /// Files and folders are handed over and the window that appears is taken.
        case contents(OpenRequest)
        /// Web pages go into a window opened from the menu first.
        case menuThenContents(OpenRequest)
    }

    enum Failure: Equatable {
        case notRunning
        case contentsNotOpened
        case noWindow
    }

    var action: Action
    var note: String?

    /// The window the step takes for its entry.
    var window: WindowID? {
        switch action {
        case .place(let id), .move(let id): return id
        case .launch, .open, .fail: return nil
        }
    }
}

/// Decides how each entry gets its window, by the first rule of design 5.2 that applies. Pure:
/// the windows, the running applications and their menus are read by the caller.
enum ExpansionPlanner {
    struct Situation {
        /// The windows showing on the target desktop, in the service's order.
        var here: [WindowInfo]
        /// Every other window.
        var elsewhere: [WindowInfo]
        /// Bundle IDs of running applications; one with a window counts as running anyway.
        var running: Set<String>
        /// Bundle ID → whether the application has a "new window" item; absent when unknown.
        var canOpenNewWindow: [String: Bool] = [:]
        var options: WorkspaceOptions
    }

    /// One step per entry. `settled` entries keep the windows they have, which no other entry gets.
    static func plan(_ entries: [SavedWindow], in situation: Situation, settled: [Int: WindowID] = [:]) -> [ExpansionStep] {
        // Rule 1, paired as when a checkpoint is saved over.
        let matches = WindowMatcher.match(entries, with: situation.here.map(WindowIdentity.init), reserved: settled,
                                          contentsMustAgree: false)
        var used = Set(matches.values)
        return entries.indices.map { index in
            if let id = matches[index] { return ExpansionStep(action: .place(id)) }
            let step = step(for: entries[index], in: situation, used: used)
            if let id = step.window { used.insert(id) }
            return step
        }
    }

    /// Said of an entry that got its window without its contents, "打开记录的内容" being off.
    static var contentsSkipped: String { L10n.text("workspaces.contents.not.opened") }

    /// With "打开记录的内容" off, an entry with contents is decided as one without, and what it
    /// gets says so.
    private static func step(for entry: SavedWindow, in situation: Situation, used: Set<WindowID>) -> ExpansionStep {
        guard !entry.contents.isEmpty, !situation.options.reopensMissingWindows else {
            return decide(entry, in: situation, used: used)
        }
        var bare = entry
        bare.contents = []
        var step = decide(bare, in: situation, used: used)
        if case .fail = step.action { return step }
        step.note = step.note.map { $0 + L10n.text("text.reasonSeparator") + contentsSkipped } ?? contentsSkipped
        return step
    }

    /// Rules 2 to 6 for an entry without a window on the target desktop.
    private static func decide(_ entry: SavedWindow, in situation: Situation, used: Set<WindowID>) -> ExpansionStep {
        guard let bundle = entry.bundleID.nonEmpty else {
            return ExpansionStep(action: .fail(.noWindow), note: L10n.text("workspaces.this.entry.has.no.application.identifier"))
        }
        func own(_ window: WindowInfo) -> Bool { window.bundleID == bundle && !used.contains(window.id) }
        // A minimized or full-screen window is not brought over from another desktop.
        let movable = situation.elsewhere.filter { !$0.isMinimized && !$0.isFullscreen }
        // Rule 2: the window used last time, its number and process unchanged.
        if let ref = entry.lastWindow,
           let last = movable.first(where: { own($0) && $0.id == ref.windowID && $0.pid == ref.pid }) {
            return ExpansionStep(action: .move(last.id))
        }
        // Rule 3: a file or folder is open once per application. Web pages are opened anew.
        let isWeb = entry.contents.contains { $0.kind == .webPage }
        if !isWeb, let document = entry.documentIdentity {
            func shows(_ window: WindowInfo) -> Bool { own(window) && WindowIdentity(window).documentURL == document }
            if let showing = situation.here.first(where: shows) { return ExpansionStep(action: .place(showing.id)) }
            if let showing = movable.first(where: shows) { return ExpansionStep(action: .move(showing.id)) }
        }
        let windows = (situation.here + movable).filter(own)
        let isRunning = situation.running.contains(bundle)
            || (situation.here + situation.elsewhere).contains { $0.bundleID == bundle }
        guard isRunning else {
            guard situation.options.launchesMissingApps else { return ExpansionStep(action: .fail(.notRunning)) }
            guard entry.windowing != .onlyWindow, !entry.contents.isEmpty else {
                return ExpansionStep(action: .launch(OpenRequest(bundleID: bundle)))
            }
            return withContents(entry) { .launch($0) }
        }
        let canOpen = situation.canOpenNewWindow[bundle]
        switch kind(of: entry, canOpen: canOpen) {
        case nil:
            return ExpansionStep(action: .fail(.noWindow), note: L10n.text("workspaces.could.not.read.the.application.menu"))
        case .single?:
            // Rule 4: its window comes here, also from a desktop another workspace owns.
            let titled = windows.first { $0.title == entry.title }
            guard let chosen = titled ?? windows.first else {
                // An application without any window, as Music with its window closed, is asked
                // for it the way one is launched.
                let hasNone = !(situation.here + situation.elsewhere).contains { $0.bundleID == bundle }
                guard hasNone, situation.options.launchesMissingApps else {
                    return ExpansionStep(action: .fail(.noWindow), note: L10n.text("workspaces.the.app.has.no.available.windows"))
                }
                return ExpansionStep(action: .launch(OpenRequest(bundleID: bundle)))
            }
            let isHere = situation.here.contains { $0.id == chosen.id }
            return ExpansionStep(action: isHere ? .place(chosen.id) : .move(chosen.id),
                                 note: titled == nil && windows.count > 1 ? L10n.text("workspaces.matched.by.application") : nil)
        case .multi?:
            // Rule 5.
            guard !entry.contents.isEmpty else { return ExpansionStep(action: .open(.menu)) }
            return withContents(entry) { request in
                // Without the menu item a page can only be handed over.
                .open(isWeb && canOpen != false ? .menuThenContents(request) : .contents(request))
            }
        }
    }

    private enum Kind { case single, multi }

    /// Design 5.3. Nil when the menus could not be read and the entry has no contents to tell:
    /// taking the application for single-window would bring its window over from another desktop.
    private static func kind(of entry: SavedWindow, canOpen: Bool?) -> Kind? {
        switch entry.windowing {
        case .newWindow: return .multi
        case .onlyWindow: return .single
        case .automatic:
            if !entry.contents.isEmpty || canOpen == true { return .multi }
            return canOpen == false ? .single : nil
        }
    }

    /// Handing over contents needs targets that can be opened.
    private static func withContents(_ entry: SavedWindow, _ action: (OpenRequest) -> ExpansionStep.Action) -> ExpansionStep {
        guard let request = entry.openRequest else {
            let reason = entry.contents.lazy.compactMap { $0.validationError(bundleID: entry.bundleID) }.first
            return ExpansionStep(action: .fail(.contentsNotOpened), note: reason ?? L10n.text("workspaces.cannot.open.this.target"))
        }
        return ExpansionStep(action: action(request))
    }
}

extension ExpansionPlanner.Situation {
    /// Splits `windows` by whether they show on `target`. When no window says where it is, as
    /// without the private Space queries, all count as being there.
    init(windows: [WindowInfo], target: SpaceID, running: Set<String>, canOpenNewWindow: [String: Bool] = [:],
         options: WorkspaceOptions) {
        let known = windows.contains { !$0.spaceIDs.isEmpty }
        self.init(here: windows.filter { !known || $0.spaceIDs.contains(target) },
                  elsewhere: windows.filter { known && !$0.spaceIDs.contains(target) },
                  running: running, canOpenNewWindow: canOpenNewWindow, options: options)
    }
}
