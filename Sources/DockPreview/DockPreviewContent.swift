import Contracts
import CoreGraphics

/// One window in the preview.
struct DockPreviewCard: Equatable, Identifiable {
    var window: WindowInfo
    /// nil until captured, and always without Screen Recording permission.
    var thumbnail: CGImage?
    var size: CGSize

    var id: WindowID { window.id }
}

/// Everything the preview panel shows for one app.
struct DockPreviewContent: Equatable {
    var item: DockItem
    var cards: [DockPreviewCard]
    /// Lines explaining what is missing, e.g. thumbnails without Screen Recording permission.
    var notices: [String]
    var layout: DockPreviewLayout

    /// `area` is the size of the visible area the panel must fit in.
    init(item: DockItem, windows: [WindowInfo], thumbnails: [WindowID: CGImage], notices: [String], area: CGSize) {
        self.item = item
        self.notices = notices
        layout = DockPreviewLayout(windowSizes: windows.map(\.frame.size), dockEdge: item.dockEdge,
                                   noticeCount: notices.count, area: area)
        cards = zip(windows, layout.cardSizes).map { window, size in
            DockPreviewCard(window: window, thumbnail: thumbnails[window.id], size: size)
        }
    }
}

/// What the cards' buttons do; the controller supplies them.
struct DockPreviewActions {
    var choose: @MainActor (WindowID) -> Void
    var close: @MainActor (WindowID) -> Void
    var minimize: @MainActor (WindowID) -> Void
}
