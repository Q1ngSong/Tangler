import CoreKit
import AppKit
import Contracts
import OverlayKit
import SwiftUI

/// One workspace on the settings page: name, checkpoint line, preview, its actions, the app
/// list with an editor per entry, the options and the last expansion report.
struct WorkspaceDetailView: View {
    let controller: WorkspacesController
    let workspace: Workspace
    @Binding var message: String?
    @Binding var selection: UUID?
    @State private var name = ""
    @State private var editing: SavedWindow?
    @State private var tab = DetailTab.overview
    @State private var renaming = false
    @Environment(\.settingsCompactLayout) private var compact

    private enum DetailTab: String, CaseIterable {
        case overview, options, history
        var title: String {
            switch self {
            case .overview: L10n.text("workspace.detail.overview")
            case .options: L10n.text("workspaces.launch.options")
            case .history: L10n.text("workspace.detail.history")
            }
        }
    }

    private var detailTabs: some View {
        Picker(L10n.text("workspaces.workspace.details"), selection: $tab) {
            ForEach(DetailTab.allCases, id: \.self) { Text($0.title).tag($0) }
        }.labelsHidden()
    }

    private var library: WorkspaceLibrary { controller.library }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(workspace.name).font(SettingsTypography.sectionTitle).lineLimit(1)
                    if workspace.isLocked { Image(systemName: "lock.fill").foregroundStyle(.secondary) }
                    Spacer()
                    moreActions
                }
                Text(controller.state(of: workspace.id).label).font(SettingsTypography.caption).foregroundStyle(.secondary)
                actions
            }
            if compact {
                detailTabs.pickerStyle(.menu)
            } else {
                detailTabs.pickerStyle(.segmented)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch tab {
                    case .overview:
                        SettingsPreview(L10n.text("workspaces.window.layout"), aspectRatio: 16.0 / 10, maxWidth: 480) {
                            WorkspacePreview(workspace: workspace, fallbackAspect: Self.mainAspect, height: nil) { entry in
                                library.selectPreviewWindow(entry, in: workspace.id)
                            }.padding(12)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(EntrySummary.checkpointLine(for: workspace))
                            if !workspace.windows.isEmpty {
                                if let focused = workspace.windows.first(where: { $0.id == workspace.options.focusedWindow }) {
                                    Text(L10n.text("workspaces.focus.on.open.click.a.tab.or", String(describing: (focused.appName))))
                                        .help(WorkspacePreview.tooltip(for: focused))
                                } else {
                                    Text(L10n.text("workspaces.click.a.tab.or.window.to.focus"))
                                }
                            }
                        }.font(SettingsTypography.caption).foregroundStyle(.secondary)
                        WorkspaceAppList(workspace: workspace) { editing = $0 }
                    case .options: options
                    case .history: lastReport
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(compact ? 12 : SettingsPageLayout.contentInset)
        .onAppear { name = workspace.name }
        .onChange(of: workspace.id) { name = workspace.name; tab = .overview }
        .sheet(isPresented: $renaming) {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.text("workspaces.rename.workspace")).font(SettingsTypography.sectionTitle)
                TextField(L10n.text("workspaces.name"), text: $name).textFieldStyle(.roundedBorder).onSubmit { rename(); renaming = false }
                HStack {
                    Spacer()
                    Button(L10n.text("workspaces.cancel"), role: .cancel) { renaming = false }
                    Button(L10n.text("overlaykit.save")) { rename(); renaming = false }
                        .keyboardShortcut(.defaultAction)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(24).frame(width: 320)
        }
        .sheet(item: $editing) { entry in
            ItemEditor(entry: entry, save: { rows, windowing in
                ItemEdit.save(rows: rows, windowing: windowing, for: entry, in: workspace.id, library: library)
            }, remove: { try? library.removeEntry(entry.id, from: workspace.id) })
        }
    }

    private var moreActions: some View {
        Menu(L10n.text("workspaces.more"), systemImage: "ellipsis") {
            Button(L10n.text("workspaces.rename")) { name = workspace.name; renaming = true }
            if WorkspaceAction.offered(for: controller.state(of: workspace.id)).contains(.release) {
                Button(L10n.text("workspaces.release")) { Task { show(await controller.release(workspace.id)) } }
                Button(L10n.text("workspaces.release.and.remove.desktop")) { Task { show(await controller.release(workspace.id, removingDesktop: true)) } }
            }
            Divider()
            button(for: .delete)
        }
        .menuStyle(.borderlessButton).fixedSize().help(L10n.text("workspaces.more.workspace.actions"))
    }

    /// The main display's visible frame, for checkpoints saved before the aspect was recorded.
    private static var mainAspect: Double {
        guard let frame = NSScreen.main?.visibleFrame, frame.height > 0 else { return 1.6 }
        return Double(frame.width / frame.height)
    }

    /// Primary operations stay above the preview; their disabled reasons remain visible.
    private var actions: some View {
        let state = controller.state(of: workspace.id)
        let obstacles = controller.obstacles(for: workspace.id)
        let offered = WorkspaceAction.offered(for: state)
        func isOff(_ action: WorkspaceAction) -> Bool { action.disabledReason(for: state, obstacles: obstacles) != nil }
        return VStack(alignment: .leading, spacing: 8) {
            (compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout())) {
                ForEach(offered.filter { !$0.isInSecondRow }) { button(for: $0).disabled(isOff($0)) }
            }
            if controller.isExpanding {
                Button(L10n.text("workspaces.cancel.expansion")) { controller.cancelExpansion() }.controlSize(.small)
            }
            ForEach(WorkspaceAction.reasonLines(for: state, obstacles: obstacles), id: \.self) { line in
                Text(line).font(SettingsTypography.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func button(for action: WorkspaceAction) -> some View {
        switch action {
        case .open:
            Button(action.title) { show(controller.open(workspace)) }
                .buttonStyle(.borderedProminent)
        case .goToDesktop:
            Button(action.title) { show(controller.open(workspace)) }
        case .saveCheckpoint:
            // The checkpoint is taken from the workspace's own desktop.
            Button(action.title) {
                Task { message = await controller.saveCheckpoint(workspace.id) }
            }
        case .revert:
            Button(action.title) { show(controller.revert(workspace)) }
        case .release:
            Menu(action.title) {
                Button(L10n.text("workspaces.release.and.remove.desktop")) {
                    Task { show(await controller.release(workspace.id, removingDesktop: true)) }
                }
            } primaryAction: {
                Task { show(await controller.release(workspace.id)) }
            }
            .fixedSize()
        case .delete:
            Button(action.title, role: .destructive) {
                let next = library.neighbour(of: workspace.id)
                controller.delete(workspace.id)
                selection = next
                message = L10n.text("workspaces.moved.to.trash.you.can.restore.it", String(describing: (workspace.name)), String(describing: (WorkspaceLibrary.binDays)))
            }
        }
    }

    private var options: some View {
        GroupBox(L10n.text("workspaces.launch.options")) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(L10n.text("workspaces.lock.as.template.manual.saves.only"), isOn: Binding(
                    get: { library.workspace(id: workspace.id)?.isLocked ?? workspace.isLocked },
                    set: { library.setLocked($0, for: workspace.id) }))
                Toggle(L10n.text("workspaces.launch.apps.that.are.not.running"), isOn: option(\.launchesMissingApps))
                Toggle(L10n.text("workspaces.open.recorded.contents"), isOn: option(\.reopensMissingWindows))
                Text(L10n.text("workspaces.existing.windows.are.placed.without.opening.duplicates"))
                    .font(SettingsTypography.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var lastReport: some View {
        if let report = controller.lastReport, report.workspaceID == workspace.id {
            GroupBox(report.isFinished ? L10n.text("workspaces.last.expansion") : L10n.text("workspaces.expanding")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(report.summary).font(SettingsTypography.body)
                    ForEach(report.entries) { ExpansionEntryRow(entry: $0) }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView(L10n.text("workspaces.no.expansion.history"), systemImage: "clock.arrow.circlepath",
                                   description: Text(L10n.text("workspaces.open.the.workspace.to.see.the.restoration")))
        }
    }

    /// Reads and writes the stored options, so an edit never works on a stale copy.
    private func option<Value>(_ key: WritableKeyPath<WorkspaceOptions, Value>) -> Binding<Value> {
        let id = workspace.id
        let fallback = workspace.options
        return Binding(get: { library.workspace(id: id)?.options[keyPath: key] ?? fallback[keyPath: key] },
                       set: { value in
                           var options = library.workspace(id: id)?.options ?? fallback
                           options[keyPath: key] = value
                           library.setOptions(options, for: id)
                       })
    }

    private func rename() {
        do {
            // The stored name is trimmed; showing it also turns "重命名" off again.
            name = try library.rename(workspace.id, to: name)
            message = nil
        } catch {
            message = WorkspacesController.message(for: error)
        }
    }

    private func show(_ result: CommandResult) {
        switch result {
        case .done: message = nil
        case .unavailable(let reason), .failed(let reason): message = reason
        }
    }
}

/// The buttons under a workspace's preview (workspaces design section 8).
enum WorkspaceAction: Identifiable, CaseIterable {
    case open, goToDesktop, saveCheckpoint, revert, release, delete

    var id: Self { self }

    var title: String {
        switch self {
        case .open: return L10n.text("workspaces.open")
        case .goToDesktop: return L10n.text("workspaces.switch.to.desktop")
        case .saveCheckpoint: return L10n.text("workspaces.save.checkpoint")
        case .revert: return L10n.text("workspaces.restore.checkpoint")
        case .release: return L10n.text("workspaces.release")
        case .delete: return L10n.text("workspaces.delete")
        }
    }

    var isInSecondRow: Bool { self == .release || self == .delete }

    /// A workspace that is not open can only be opened; "删除" is always there.
    static func offered(for state: WorkspaceDesktops.State) -> [WorkspaceAction] {
        switch state {
        case .closed: return [.open, .delete]
        case .open: return [.goToDesktop, .saveCheckpoint, .revert, .release, .delete]
        }
    }
}

/// What is in the way of a workspace's buttons right now, each with the text that says so.
struct WorkspaceObstacles: Equatable {
    /// The Accessibility permission is missing: no window can be read or moved.
    var permission: String?
    /// There is no placement service to expand a checkpoint with.
    var placement: String?
    /// Desktops cannot be added, which opening a workspace that is not open needs.
    var addingDesktops: String?
    /// The windows of desktops that are not showing cannot be read.
    var otherDesktops: String?
    /// The workspace is being opened or expanded.
    var isExpanding = false
}

extension WorkspaceAction {
    /// Why the button cannot work, or nil when it can.
    func disabledReason(for state: WorkspaceDesktops.State, obstacles: WorkspaceObstacles) -> String? {
        switch self {
        case .open:
            return obstacles.placement ?? obstacles.permission ?? obstacles.addingDesktops
        case .goToDesktop, .revert:
            return obstacles.placement ?? obstacles.permission
        case .saveCheckpoint:
            if let permission = obstacles.permission { return permission }
            if obstacles.isExpanding { return L10n.text("workspaces.expansion.is.in.progress.wait.before.saving") }
            // The checkpoint is taken from the workspace's own desktop.
            if case .open(let desktop) = state, !desktop.isCurrent, let reason = obstacles.otherDesktops {
                return L10n.text("workspaces.this.workspace.s.desktop.is.not.visible", String(describing: (reason)))
            }
            return nil
        case .release, .delete:
            return nil
        }
    }

    /// One line per reason, in the order of the buttons, naming the buttons it turns off:
    /// "切到桌面、恢复到检查点：…".
    static func reasonLines(for state: WorkspaceDesktops.State, obstacles: WorkspaceObstacles) -> [String] {
        let off = offered(for: state).compactMap { action in
            action.disabledReason(for: state, obstacles: obstacles).map { (title: action.title, reason: $0) }
        }
        var reasons: [String] = []
        for button in off where !reasons.contains(button.reason) { reasons.append(button.reason) }
        return reasons.map { reason in
            L10n.text("text.itemsWithReason", off.filter { $0.reason == reason }.map(\.title).joined(separator: L10n.text("text.itemSeparator")), reason)
        }
    }
}
