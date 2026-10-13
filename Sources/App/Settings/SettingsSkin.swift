import AppKit
import Contracts
import OverlayKit
import SwiftUI

// Both skins share the settings layout and keyboard-selectable navigation list. Liquid Glass uses a
// full-size content view; the classic window keeps a plain title bar.

extension SettingsWindowController {
    static let title = "Tangler"
    static let classicStyle: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
    /// Classic's content size, below a plain title bar.
    static let contentSize = NSSize(width: 1040, height: 698)
    /// Liquid Glass's content includes its title bar, so its frame is set directly.
    static let liquidGlassFrameSize = NSSize(width: 1040, height: 720)
    /// The smallest content the user can resize to; pages scroll below their own height.
    static let minimumContentSize = NSSize(width: 480, height: 600)

    /// Gives the window its style, toolbar, title and size for `skin` and puts `content` in it.
    /// The content owns the brand and page headings. This never centers the window, makes it
    /// key or puts it on a display: the controller does that, and the gallery never does.
    static func configure(_ window: NSWindow, content: NSViewController, skin: Skin) {
        switch skin {
        case .classic:
            window.contentViewController = content
            window.title = title
            window.styleMask = classicStyle
            window.setContentSize(contentSize)
        case .liquidGlass:
            window.title = title
            window.styleMask = classicStyle.union(.fullSizeContentView)
            window.contentViewController = content
            window.setFrame(NSRect(origin: window.frame.origin, size: liquidGlassFrameSize), display: false)
        }
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.toolbar = nil
        window.titlebarAppearsTransparent = true
        window.contentMinSize = minimumContentSize
        window.minSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: minimumContentSize)).size
    }

    /// Enforce the same minimum for live resizing and rebuilding after a skin change.
    static func constrainedFrameSize(_ proposed: NSSize, for window: NSWindow) -> NSSize {
        let minimum = window.frameRect(forContentRect: NSRect(origin: .zero, size: minimumContentSize)).size
        return NSSize(width: max(proposed.width, minimum.width), height: max(proposed.height, minimum.height))
    }
}

/// What a module page says when the module has no page to show: `EmptyState` in Liquid Glass.
/// Classic keeps the text exactly as before: `EmptyState`'s classic text is a verbatim string,
/// which sets 「」 narrower than the localized text this page always used.
struct ModulePlaceholder: View {
    let message: String
    let id: ModuleID
    @Environment(\.skin) private var skin

    var body: some View {
        switch skin {
        case .classic:
            Text(LocalizedStringKey(message)).foregroundStyle(.secondary)
        case .liquidGlass:
            // Centered in the page, as System Settings shows its empty states.
            EmptyState(message, systemImage: FeatureCatalog.symbol(for: id))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
