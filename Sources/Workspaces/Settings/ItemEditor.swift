import CoreKit
import OverlayKit
import SwiftUI

/// What "保存" in an entry's editor stores.
@MainActor
enum ItemEdit {
    /// The rows that name something, trimmed.
    nonisolated static func contents(from rows: [ReopenTarget]) -> [ReopenTarget] {
        rows.map { ReopenTarget(kind: $0.kind, target: $0.target.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.target.isEmpty }
    }

    /// Returns an error message, or nil when the entry was saved. Contents are written only when
    /// they differ from the entry's, so changing the windowing does not mark detected contents
    /// as custom; refused contents store nothing.
    static func save(rows: [ReopenTarget], windowing: Windowing, for entry: SavedWindow, in workspace: UUID,
                     library: WorkspaceLibrary) -> String? {
        let contents = contents(from: rows)
        do {
            if contents != entry.contents { try library.setContents(contents, forWindow: entry.id, in: workspace) }
            try library.setWindowing(windowing, forWindow: entry.id, in: workspace)
            return nil
        } catch {
            return WorkspacesController.message(for: error)
        }
    }
}

/// Edits what one entry opens and how it gets its window. Saving opens nothing.
struct ItemEditor: View {
    let entry: SavedWindow
    /// Returns an error message, or nil when the entry was saved.
    let save: (_ rows: [ReopenTarget], _ windowing: Windowing) -> String?
    let remove: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [Row]
    @State private var windowing: Windowing
    @State private var error: String?

    /// A target being typed; the identity keeps a row's field while others are removed.
    private struct Row: Identifiable, Equatable {
        let id = UUID()
        var target: ReopenTarget
    }

    init(entry: SavedWindow, save: @escaping (_ rows: [ReopenTarget], _ windowing: Windowing) -> String?,
         remove: @escaping () -> Void) {
        self.entry = entry
        self.save = save
        self.remove = remove
        _rows = State(initialValue: entry.contents.map { Row(target: $0) })
        _windowing = State(initialValue: entry.windowing)
    }

    /// The first row that would be refused, shown before saving.
    private var problem: String? {
        ItemEdit.contents(from: rows.map(\.target)).lazy.compactMap { $0.validationError(bundleID: entry.bundleID) }.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(WorkspacePreview.tooltip(for: entry)).font(SettingsTypography.sectionTitle).lineLimit(2)
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("workspaces.open.contents")).font(SettingsTypography.sectionTitle)
                ForEach($rows) { $row in
                    HStack {
                        Picker(L10n.text("workspaces.type"), selection: $row.target.kind) {
                            ForEach(ReopenTarget.Kind.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden().frame(width: 96)
                        TextField(row.target.kind == .webPage ? "https://example.com/page" : L10n.text("workspaces.absolute.path.to.file.or.folder"),
                                  text: $row.target.target)
                            .textFieldStyle(.roundedBorder)
                        Button { rows.removeAll { $0.id == row.id } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).help(L10n.text("workspaces.remove.this.item"))
                    }
                }
                Button(L10n.text("workspaces.add")) { rows.append(Row(target: ReopenTarget(kind: .webPage, target: ""))) }
                if let text = error ?? problem {
                    Text(text).font(SettingsTypography.caption).foregroundStyle(.red)
                }
                Text(L10n.text("workspaces.only.absolute.paths.file.urls.and.complete"))
                    .font(SettingsTypography.caption).foregroundStyle(.secondary)
            }
            Picker(L10n.text("workspaces.window.behavior"), selection: $windowing) {
                ForEach(Windowing.allCases) { Text($0.label).tag($0) }
            }
            HStack {
                Button(L10n.text("workspaces.remove.this.entry"), role: .destructive) {
                    remove()
                    dismiss()
                }
                Spacer()
                Button(L10n.text("workspaces.cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.text("overlaykit.save")) {
                    error = save(rows.map(\.target), windowing)
                    if error == nil { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onChange(of: rows) { error = nil }
    }
}
