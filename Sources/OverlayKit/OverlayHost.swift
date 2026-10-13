import AppKit
import SwiftUI

/// Where `OverlayHost` puts its panel among the other windows.
public enum OverlayOrdering: Equatable, Sendable {
    /// In front of every window at the panel's level.
    case front
    /// Just above the window with this window server number, e.g. a tab bar over its window.
    case above(windowNumber: Int)
}

/// Shows a SwiftUI view in an `OverlayPanel` at a frame given in global coordinates.
/// The panel is created on first use and reused; `hide()` keeps it for the next `show`.
/// Content is drawn and measured in the skin the user chose (`SkinnedRoot`).
@MainActor
public final class OverlayHost<Content: View> {
    public let style: OverlayStyle
    /// The global frame of the last `show`.
    public private(set) var frame: CGRect?
    /// The panel once shown, e.g. to fade it; nil before the first `show`.
    public private(set) var panel: OverlayPanel?
    private var hostingView: OverlayHostingView<SkinnedRoot<Content>>?
    private var measurer: NSHostingController<SkinnedRoot<Content>>?

    public init(style: OverlayStyle = .interactive) {
        self.style = style
    }

    /// `OverlayPanel.isConcealed` for the panel, also for one that is made later: it comes on
    /// screen concealed.
    public var isConcealed = false {
        didSet { panel?.isConcealed = isConcealed }
    }

    public var isVisible: Bool { panel?.isVisible ?? false }

    /// Shows `content` filling `frame`. Calling it again while visible moves the panel and
    /// replaces the content; `ordering` applies when the panel comes on screen. A keyboard style
    /// makes the panel key.
    public func show(_ content: Content, in frame: CGRect, ordering: OverlayOrdering = .front) {
        let panel = preparedPanel(showing: content)
        self.frame = frame
        let appKitFrame = OverlayGeometry.appKitFrame(for: frame, primaryHeight: OverlayGeometry.primaryDisplayHeight)
        if panel.frame != appKitFrame { panel.setFrame(appKitFrame, display: true) }
        if !panel.isVisible {
            // Lay the new content out first so a reused panel does not flash its old content.
            panel.contentView?.layoutSubtreeIfNeeded()
            order(ordering)
        }
        if style.acceptsKeyboard && !panel.isKeyWindow { panel.makeKey() }
    }

    /// Puts the shown panel back in its place, e.g. after its window was raised above it.
    public func order(_ ordering: OverlayOrdering) {
        guard let panel else { return }
        switch ordering {
        case .front: panel.orderFrontRegardless()
        case .above(let number): panel.order(.above, relativeTo: number)
        }
    }

    /// Shows `content` at its fitting size, measured against the placement's area, so give
    /// the content an ideal size (e.g. `.fixedSize()`); flexible content fills the area.
    public func show(_ content: Content, placement: OverlayPlacement) {
        show(content, in: placement.frame(for: fittingSize(for: content, within: placement.bounds.size)))
    }

    /// Replaces the content and keeps the frame.
    public func update(_ content: Content) {
        hostingView?.rootView = SkinnedRoot(content: content)
    }

    public func hide() {
        panel?.orderOut(nil)
    }

    /// The size `content` takes when offered at most `limit`.
    public func fittingSize(for content: Content, within limit: CGSize) -> CGSize {
        let root = SkinnedRoot(content: content)
        let measurer = self.measurer ?? NSHostingController(rootView: root)
        measurer.rootView = root
        self.measurer = measurer
        let size = measurer.sizeThatFits(in: limit)
        return CGSize(width: min(size.width, limit.width), height: min(size.height, limit.height))
    }

    func preparedPanel(showing content: Content) -> OverlayPanel {
        if let panel, let hostingView {
            hostingView.rootView = SkinnedRoot(content: content)
            return panel
        }
        let panel = OverlayPanel(style: style)
        panel.isConcealed = isConcealed
        let hostingView = OverlayHostingView(rootView: SkinnedRoot(content: content))
        hostingView.configureForOverlay()
        panel.contentView = hostingView
        self.panel = panel
        self.hostingView = hostingView
        return panel
    }
}
