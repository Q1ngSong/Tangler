import CoreKit
import CoreGraphics
import Foundation

/// The short texts of the settings page's app list.
enum EntrySummary {
    /// One row of the app list.
    struct Row: Equatable, Identifiable {
        var entry: SavedWindow
        /// "应用 — 标题".
        var title: String
        /// The zone, the tab position for an entry in a tab group, and the contents.
        var caption: String

        var id: UUID { entry.id }
    }

    /// A row per entry, entries of one application next to each other.
    static func rows(for workspace: Workspace) -> [Row] {
        ordered(workspace.windows).map { entry in
            Row(entry: entry, title: WorkspacePreview.tooltip(for: entry), caption: caption(for: entry, in: workspace))
        }
    }

    static func caption(for entry: SavedWindow, in workspace: Workspace) -> String {
        [ZoneName.name(for: entry.unitFrame), tab(of: entry, in: workspace), contents(of: entry)]
            .compactMap { $0 }.joined(separator: " · ")
    }

    static func contents(of entry: SavedWindow) -> String {
        guard let first = entry.contents.first else { return L10n.text("workspaces.place.only") }
        guard entry.contents.count > 1 else {
            let url = first.resourceURL
            let name = first.kind == .webPage ? url?.host() : url?.lastPathComponent
            return "\(first.kind.label) \(name ?? first.target)"
        }
        if entry.contents.allSatisfy({ $0.kind == .webPage }) { return L10n.count("workspaces.pages", entry.contents.count) }
        return L10n.count("workspaces.items", entry.contents.count)
    }

    /// "第 N 个标签" for an entry in a tab group, counted as the preview draws its tabs.
    static func tab(of entry: SavedWindow, in workspace: Workspace) -> String? {
        let tiles = PreviewLayout.tiles(for: workspace, on: CGSize(width: 1, height: 1)).filter(\.showsTabBar)
        return tiles.lazy.compactMap { $0.tabs.firstIndex(of: entry.id) }.first.map { L10n.text("workspaces.tab", String(describing: ($0 + 1))) }
    }

    /// Entries of one application next to each other, applications in the order they first appear.
    static func ordered(_ entries: [SavedWindow]) -> [SavedWindow] {
        var order: [String] = []
        for entry in entries where !order.contains(key(entry)) { order.append(key(entry)) }
        return order.flatMap { app in entries.filter { key($0) == app } }
    }

    static func checkpointLine(for workspace: Workspace, time: (Date) -> String = defaultTime) -> String {
        guard !workspace.windows.isEmpty else { return L10n.text("workspaces.no.checkpoint.yet") }
        let apps = L10n.count("workspaces.apps", workspace.appCount)
        return workspace.savedAt.map { L10n.text("workspaces.checkpoint", String(describing: (time($0))), String(describing: (apps))) } ?? L10n.text("workspaces.checkpoint.entrysummary", String(describing: (apps)))
    }

    static func defaultTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = L10n.current.locale
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func key(_ entry: SavedWindow) -> String { entry.bundleID ?? entry.appName }
}
