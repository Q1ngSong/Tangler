import Contracts
import CoreGraphics
import Observation

/// One card. Its own observable object, so a live frame redraws only the selected card.
@MainActor
@Observable
final class SwitcherItem: Identifiable {
    let id: WindowID
    var window: WindowInfo
    /// The latest thumbnail or live frame; nil shows the app icon instead.
    var image: CGImage?

    init(window: WindowInfo) {
        id = window.id
        self.window = window
    }
}

/// What the switcher panel shows: the windows, the selection and the notes underneath.
@MainActor
@Observable
final class SwitcherModel {
    /// What the panel's cards report; the controller fills these in.
    struct Actions {
        var hover: (WindowID) -> Void = { _ in }
        var choose: (WindowID) -> Void = { _ in }
    }

    private(set) var items: [SwitcherItem]
    private(set) var selectedID: WindowID?
    /// The card to bring into view. Keyboard steps set it and hovering does not: scrolling
    /// would slide another card under a resting pointer, which would then select that one.
    private(set) var scrollTarget: WindowID?
    /// Lines under the cards, e.g. why thumbnails or other Spaces are missing.
    let notices: [String]
    let previewHeight: CGFloat
    /// The widest the strip may get; beyond it the cards scroll.
    var maxStripWidth: CGFloat
    @ObservationIgnored var actions = Actions()

    init(windows: [WindowInfo], selectedIndex: Int?, notices: [String] = [], previewHeight: CGFloat,
         maxStripWidth: CGFloat = .infinity) {
        let selected = selectedIndex.flatMap { windows.indices.contains($0) ? windows[$0].id : nil }
        items = windows.map(SwitcherItem.init)
        selectedID = selected
        scrollTarget = selected
        self.notices = notices
        self.previewHeight = previewHeight
        self.maxStripWidth = maxStripWidth
    }

    var selectedIndex: Int? { items.firstIndex { $0.id == selectedID } }
    var selected: WindowInfo? { selectedIndex.map { items[$0].window } }

    var stripWidth: CGFloat {
        min(SwitcherLayout.stripWidth(for: items.map(\.window), previewHeight: previewHeight), maxStripWidth)
    }

    func item(_ id: WindowID) -> SwitcherItem? { items.first { $0.id == id } }

    /// Steps through the cards, wrapping around at both ends.
    func move(by offset: Int) {
        guard !items.isEmpty else { return }
        let current = selectedIndex ?? 0
        let count = items.count
        selectedID = items[((current + offset) % count + count) % count].id
        scrollTarget = selectedID
    }

    func select(_ id: WindowID) {
        guard item(id) != nil else { return }
        selectedID = id
    }

    /// Drops a closed window. When it was selected, the card taking its place is selected,
    /// or the one before it at the end of the list.
    @discardableResult
    func remove(_ id: WindowID) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        items.remove(at: index)
        if selectedID == id {
            selectedID = items.isEmpty ? nil : items[min(index, items.count - 1)].id
            scrollTarget = selectedID
        }
        return true
    }

    /// A still never replaces a picture already there, which may be a newer live frame.
    func setImage(_ image: CGImage, for id: WindowID, live: Bool) {
        guard let item = item(id), live || item.image == nil else { return }
        item.image = image
    }
}
