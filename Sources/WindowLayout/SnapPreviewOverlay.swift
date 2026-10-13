import AppKit
import OverlayKit

/// What the presenter asks of its panel: an `OverlayPanel` in the app, a stand-in in tests.
@MainActor
protocol SnapPreviewPanel: AnyObject {
    var level: NSWindow.Level { get set }
    var contentView: NSView? { get set }
    func setFrame(_ frameRect: NSRect, display flag: Bool)
    func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int)
    func orderFrontRegardless()
    func orderOut(_ sender: Any?)
}

extension OverlayPanel: SnapPreviewPanel {}

/// The snap preview in a click-through panel over the display under the pointer, just below
/// the dragged window. It grows out of the window, crossfades between zones and fades out
/// (snap preview animation design).
@MainActor
final class OverlaySnapPreviewPresenter: SnapPreviewPresenter {
    var animates = true
    var ordersBelowWindow = false
    var prefersGlass = false
    /// The layers; tests read it to tell when a fade has ended.
    let view = SnapPreviewLayerView(frame: .zero)
    private let panel: any SnapPreviewPanel
    private let reduceMotion: () -> Bool
    private let primaryHeight: @MainActor () -> CGFloat
    private let zones: @MainActor () -> ZoneStyles
    private var shown: SnapPreview?
    /// Where the panel is, in AppKit coordinates; nil before the first show.
    private var panelFrame: CGRect?
    /// Bumped by every show and hide, so a fade-out that ends after a newer show leaves the panel up.
    private var generation = 0

    convenience init() {
        self.init(panel: OverlayPanel(style: .hud))
    }

    /// `panel` is the app's click-through `OverlayPanel`, or a stand-in in tests. `zones` is
    /// injected the same way as `reduceMotion` and `primaryHeight`: tests give their own value,
    /// so they never touch the global `CurrentSkin` (the gallery runs its suites in parallel).
    init(panel: any SnapPreviewPanel,
         reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
         primaryHeight: @escaping @MainActor () -> CGFloat = { OverlayGeometry.primaryDisplayHeight },
         zones: @escaping @MainActor () -> ZoneStyles = { ZoneStyles.current }) {
        self.panel = panel
        self.reduceMotion = reduceMotion
        self.primaryHeight = primaryHeight
        self.zones = zones
        panel.contentView = view
    }

    func show(_ preview: SnapPreview) {
        generation += 1
        view.zones = zones()
        view.prefersGlass = prefersGlass
        let frame = OverlayGeometry.appKitFrame(for: preview.canvas, primaryHeight: primaryHeight())
        // Moving the panel empties it, so the preview then appears afresh.
        let moves = panelFrame != frame
        let change = SnapPreviewChange.between(moves ? nil : shown, and: preview, animates: animates,
                                               reduceMotion: reduceMotion())
        if moves {
            // Another display, or the displays were rearranged: move the panel there empty, so
            // nothing slides across. Back on the same display, a zone still fading out finishes its fade.
            view.apply(nil, change: .instant)
            // The emptied overlay reaches the screen before the panel moves.
            CATransaction.flush()
            panel.setFrame(frame, display: false)
            panelFrame = frame
        }
        shown = preview
        if ordersBelowWindow, let window = preview.window {
            // Among ordinary windows, just below the dragged one.
            panel.level = .normal
            panel.order(.below, relativeTo: Int(window.rawValue))
        } else {
            // Above every window, the dragged one included.
            panel.level = OverlayStyle.hud.level
            panel.orderFrontRegardless()
        }
        view.apply(preview, change: change)
    }

    func hide() {
        // Nothing shown: a fade-out under way finishes and orders the panel out itself.
        guard shown != nil else { return }
        generation += 1
        let change = SnapPreviewChange.between(shown, and: nil, animates: animates, reduceMotion: reduceMotion())
        shown = nil
        let generation = self.generation
        let panel = self.panel
        view.apply(nil, change: change) { [weak self] in
            // A newer show keeps the panel up. Without the presenter nothing can show again,
            // so the panel goes either way.
            if let self, self.generation != generation { return }
            panel.orderOut(nil)
        }
    }
}
