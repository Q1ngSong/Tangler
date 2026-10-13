import CoreKit
import Contracts
import OverlayKit
import SwiftUI

/// One list/detail layout for available workspaces and recycled checkpoints.
struct WorkspaceSettingsView: View {
    let controller: WorkspacesController
    @Environment(\.settingsCompactLayout) private var compact
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable private var navigation: WorkspaceSettingsNavigation
    @State private var newName = ""
    @State private var creating = false
    @State private var showsOptions = false
    @State private var savesDesktop = false
    @State private var message: String?
    /// The deleted workspace the user is asked about before it goes for good.
    @State private var purging: Workspace?

    init(controller: WorkspacesController, navigation: WorkspaceSettingsNavigation? = nil) {
        self.controller = controller
        self.navigation = navigation ?? WorkspaceSettingsNavigation()
    }

    private var library: WorkspaceLibrary { controller.library }
    private var visibleWorkspaces: [Workspace] { navigation.showsBin ? library.bin : library.workspaces }

    var body: some View {
        VStack(spacing: 0) {
            SettingsPageTemplate {
                VStack(spacing: 0) {
                    HStack {
                        Text(navigation.showsBin ? L10n.text("workspaces.trash") : L10n.text(compact ? "workspaces.savedList" : "workspaces.workspaces")).font(SettingsTypography.sectionTitle)
                            .lineLimit(1).minimumScaleFactor(0.75)
                        Spacer()
                        Text("\(visibleWorkspaces.count)").font(SettingsTypography.caption.monospacedDigit()).foregroundStyle(.secondary)
                        if !navigation.showsBin {
                            Menu(L10n.text("workspaces.new.workspace"), systemImage: "plus") {
                                Button(L10n.text("workspaces.empty.workspace")) { beginCreating(savingDesktop: false) }
                                Button(L10n.text("workspaces.save.current.desktop")) { beginCreating(savingDesktop: true) }
                            }
                            .labelStyle(.iconOnly).menuStyle(.borderlessButton).fixedSize()
                            .help(L10n.text("workspaces.new.workspace"))
                        }
                    }.padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 8)
                    list
                    if navigation.showsBin {
                        Divider()
                        Text(L10n.text("workspaces.deleted.workspaces.stay.in.trash.for.days", String(describing: (WorkspaceLibrary.binDays))))
                            .font(SettingsTypography.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    }
                }
            } content: {
                detail
            } headerActions: {
                HStack(spacing: 4) {
                    Button { showsOptions.toggle() } label: {
                        Image(systemName: "gearshape").font(.system(size: 18))
                            .frame(width: 30, height: 30).contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(showsOptions ? Color.accentColor : Color.primary)
                    .help(L10n.text("workspaces.workspace.settings"))
                    .accessibilityLabel(L10n.text("workspaces.workspace.settings"))
                    .popover(isPresented: $showsOptions, arrowEdge: .top) {
                        WorkspaceAutoSaveSettings(controller: controller)
                    }
                    Button {
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.22)) {
                            navigation.toggle(workspaces: library.workspaces, bin: library.bin)
                            message = nil
                        }
                    } label: {
                        SettingsTrashIcon(isOpen: navigation.showsBin).frame(width: 22, height: 22)
                            .frame(width: 30, height: 30).contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(navigation.showsBin ? Color.accentColor : Color.primary)
                    .help(navigation.showsBin ? L10n.text("workspaces.back.to.workspaces") : L10n.text("workspaces.open.trash"))
                    .accessibilityLabel(navigation.showsBin ? L10n.text("workspaces.back.to.workspaces") : L10n.text("workspaces.open.trash"))
                    .accessibilityValue(navigation.showsBin ? L10n.text("workspaces.trash.is.open") : L10n.text("workspaces.trash.is.closed"))
                }
            }
            if let message {
                Divider()
                Text(message).font(SettingsTypography.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
        }
        .sheet(isPresented: $creating) {
            VStack(alignment: .leading, spacing: 16) {
                Text(savesDesktop ? L10n.text("workspaces.save.current.desktop") : L10n.text("workspaces.new.workspace")).font(SettingsTypography.sectionTitle)
                TextField(L10n.text("workspaces.workspace.name.optional"), text: $newName)
                    .textFieldStyle(.roundedBorder).onSubmit(create)
                HStack {
                    Spacer()
                    Button(L10n.text("workspaces.cancel"), role: .cancel) { creating = false }
                    Button(L10n.text("workspaces.create"), action: create).keyboardShortcut(.defaultAction)
                }
            }.padding(24).frame(width: 340)
        }
        .onAppear(perform: reconcileSelection)
        .onChange(of: library.workspaces.map(\.id)) { reconcileSelection() }
        .onChange(of: library.bin.map(\.id)) { reconcileSelection() }
        .confirmationDialog(L10n.text("workspaces.permanently.delete", String(describing: (purging?.name ?? ""))),
                            isPresented: Binding(get: { purging != nil }, set: { if !$0 { purging = nil } }),
                            presenting: purging) { workspace in
            Button(L10n.text("workspaces.delete.now"), role: .destructive) {
                library.purge(workspace.id)
                reconcileSelection()
            }
        } message: { _ in
            Text(L10n.text("workspaces.this.cannot.be.undone"))
        }
    }

    private func beginCreating(savingDesktop: Bool) {
        newName = ""
        savesDesktop = savingDesktop
        creating = true
    }

    private func create() {
        creating = false
        if savesDesktop {
            save()
        } else {
            navigation.workspaceSelection = library.createEmpty(name: newName).id
            newName = ""
            message = nil
        }
    }

    private var list: some View {
        List(selection: $navigation.selection) {
            ForEach(visibleWorkspaces) { workspace in
                workspaceRow(workspace)
            }
            .onMove { source, destination in
                guard !navigation.showsBin else { return }
                library.move(fromOffsets: source, toOffset: destination)
            }
            .moveDisabled(navigation.showsBin)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .help(navigation.showsBin ? L10n.text("workspaces.select.a.workspace.to.inspect.and.restore") : L10n.text("workspaces.double.click.to.open.drag.to.reorder"))
        .contextMenu(forSelectionType: UUID.self) { rows in
            if navigation.showsBin, let id = rows.first, let workspace = library.bin.first(where: { $0.id == id }) {
                Button(L10n.text("workspaces.restore")) { restore(workspace) }
                Button(L10n.text("workspaces.delete.permanently"), role: .destructive) { purging = workspace }
            }
        } primaryAction: { rows in
            guard !navigation.showsBin, let workspace = rows.first.flatMap(library.workspace(id:)) else { return }
            show(controller.open(workspace))
        }
        .overlay {
            if visibleWorkspaces.isEmpty {
                Text(navigation.showsBin ? L10n.text("workspaces.trash.is.empty") : L10n.text("workspaces.no.workspaces.yet"))
                    .font(SettingsTypography.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Both lists share the same card geometry, icons, outline and selection treatment.
    private func workspaceRow(_ workspace: Workspace) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 5) {
                Text(workspace.name).font(SettingsTypography.sectionTitle).lineLimit(1)
                Spacer(minLength: 0)
                if workspace.isLocked {
                    Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(.secondary).help(L10n.text("workspaces.template.locked"))
                }
            }
            Text(navigation.showsBin ? L10n.count("workspaces.days.remaining", library.daysLeft(for: workspace)) : controller.state(of: workspace.id).label)
                .font(SettingsTypography.caption).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 4) {
                icons(of: workspace)
                Spacer(minLength: 0)
                if !navigation.showsBin, let keys = library.leaderKeys(for: workspace.id) {
                    Text(keys).font(SettingsTypography.caption.monospaced().weight(.medium)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(11).frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.primary)
        .settingsLibraryCard(selected: navigation.selection == workspace.id)
        .listRowInsets(EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .tag(workspace.id)
    }

    private func reconcileSelection() {
        navigation.reconcile(workspaces: library.workspaces, bin: library.bin)
    }

    private func restore(_ workspace: Workspace) {
        library.restore(workspace.id)
        guard library.workspace(id: workspace.id) != nil else { reconcileSelection(); return }
        navigation.workspaceSelection = workspace.id
        reconcileSelection()
        message = L10n.text("workspaces.was.restored", String(describing: (workspace.name)))
    }

    /// One icon per application, four at most; "空" before the first checkpoint.
    @ViewBuilder private func icons(of workspace: Workspace) -> some View {
        var seen = Set<String>()
        let apps = EntrySummary.ordered(workspace.windows).filter { seen.insert(EntrySummary.key($0)).inserted }
        if apps.isEmpty {
            Text(L10n.text("workspaces.empty")).font(SettingsTypography.caption).foregroundStyle(.secondary)
        } else {
            HStack(spacing: 3) {
                ForEach(apps.prefix(compact ? 2 : 4)) { entry in
                    WorkspacePreview.icon(for: entry).resizable().scaledToFit().frame(width: 18, height: 18)
                }
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let id = navigation.selection, let workspace = visibleWorkspaces.first(where: { $0.id == id }) {
            if navigation.showsBin {
                WorkspaceBinDetailView(workspace: workspace, daysLeft: library.daysLeft(for: workspace),
                                       restore: { restore(workspace) }, purge: { purging = workspace })
            } else {
                WorkspaceDetailView(controller: controller, workspace: workspace, message: $message,
                                    selection: $navigation.workspaceSelection)
            }
        } else {
            EmptyState(navigation.showsBin ? L10n.text("workspaces.trash.is.empty") : L10n.text("workspaces.select.a.workspace"),
                       systemImage: navigation.showsBin ? "trash" : "square.stack.3d.up")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func save() {
        let name = newName
        Task {
            let saved = await controller.saveCurrentDesktop(named: name)
            switch saved.result {
            case .done:
                newName = ""
                message = nil
                // The desktop's own workspace when it has one, else the new one.
                navigation.workspaceSelection = saved.workspace ?? navigation.workspaceSelection
            case .unavailable(let reason), .failed(let reason):
                message = reason
            }
        }
    }

    private func show(_ result: CommandResult) {
        switch result {
        case .done: message = nil
        case .unavailable(let reason), .failed(let reason): message = reason
        }
    }
}
