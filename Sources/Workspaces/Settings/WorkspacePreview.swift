import CoreKit
import AppKit
import Contracts
import OverlayKit
import SwiftUI

/// A checkpoint drawn as zones, tab bars and application icons (workspaces design, section 8).
struct WorkspacePreview: View {
    static let maxHeight: CGFloat = 190
    static var emptyHint: String { L10n.text("workspaces.no.checkpoint.yet.open.this.workspace.arrange") }

    let workspace: Workspace
    /// Used when the checkpoint did not record the screen's aspect.
    let fallbackAspect: Double
    var height: CGFloat? = Self.maxHeight
    var onSelect: (UUID) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { room in
            let board = PreviewLayout.boardSize(aspect: workspace.screenAspect, fallback: fallbackAspect, in: room.size)
            let tiles = PreviewLayout.tiles(for: workspace, on: board)
            ZStack(alignment: .topLeading) {
                SettingsCheckpointBackground()
                if workspace.windows.isEmpty {
                    Text(Self.emptyHint).font(SettingsTypography.body).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(12)
                        .frame(width: board.width, height: board.height)
                } else {
                    ForEach(tiles) { tile in
                        TileView(tile: tile, entries: workspace.windows) { entry in
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                                onSelect(entry)
                            }
                        }
                            .zIndex(tile.isFocused ? 1 : 0)
                            .frame(width: tile.rect.width, height: tile.rect.height)
                            .offset(x: tile.rect.minX, y: tile.rect.minY)
                    }
                }
            }
            .frame(width: board.width, height: board.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: height)
    }

    static func tooltip(for entry: SavedWindow) -> String {
        entry.title.isEmpty ? entry.appName : "\(entry.appName) — \(entry.title)"
    }

    /// The application's icon by bundle identifier, so it shows whether or not the app runs.
    @MainActor static func icon(for entry: SavedWindow?) -> Image {
        if let image = AppIconProvider.shared.icon(pid: nil, bundleID: entry?.bundleID) { return Image(nsImage: image) }
        return Image(systemName: "macwindow")
    }
}

private struct TileView: View {
    let tile: PreviewTile
    let entries: [SavedWindow]
    let select: (UUID) -> Void

    private func entry(_ id: UUID) -> SavedWindow? { entries.first { $0.id == id } }

    var body: some View {
        let activeEntry = entry(tile.active)
        SettingsCheckpointTile(title: activeEntry.map { $0.title.isEmpty ? $0.appName : $0.title } ?? "",
                               bundleID: activeEntry?.bundleID,
                               tabs: tile.showsTabBar ? tile.tabs.map { id in
                                   .init(id: id.uuidString, title: entry(id)?.appName ?? "", bundleID: entry(id)?.bundleID)
                               } : [], active: tile.active.uuidString,
                               showsNames: PreviewLayout.tabShowsName(tileWidth: tile.rect.width, tabs: tile.tabs.count),
                               focused: tile.isFocused, onSelect: { value in
                                   if let id = UUID(uuidString: value) { select(id) }
                               }, onFocus: { select(tile.active) })
        .help(entry(tile.active).map(WorkspacePreview.tooltip) ?? "")
        .padding(1)
    }
}
