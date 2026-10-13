import AppKit
import Contracts
import OverlayKit
import SwiftUI

/// The bars: one overlay panel per group, among ordinary windows just above the group's active
/// window (tab groups design 4.3). A panel belongs to the Space it came on screen on and stays
/// there, out of Mission Control (a stationary panel, `OverlayPanel.ownSpaceBehavior`). One that
/// is taken down and put up again lands on the Space showing then, so the controller puts a bar
/// up, orders and lifts it only while its group's Space shows. Without the window server's window
/// numbers the panels float above every window of their Space instead. Exposé leaves a stationary
/// panel drawn where it is, so the bars are made invisible for that time (`setHidden`), never
/// taken down.
@MainActor
final class TabBarPanels: TabBarPresenting {
    static let ghostSize = CGSize(width: 200, height: 28)

    var ordersAboveWindow = false
    private var bars: [TabGroupID: (host: OverlayHost<TabBarView>, model: TabBarModel)] = [:]
    private var isHidden = false
    private let ghost = OverlayHost<TabGhostView>(style: .hud)

    func show(_ content: TabBarContent, frame: CGRect, above window: WindowID,
              onAction: @escaping @MainActor (TabBarAction) -> Void) {
        if let bar = bars[content.group] {
            bar.model.onAction = onAction
            return apply(content, frame: frame, to: bar)
        }
        let bar = makeBar(for: content.group)
        bar.model.content = content
        bar.model.onAction = onAction
        bar.host.show(TabBarView(model: bar.model), in: frame, ordering: ordering(above: window))
    }

    func update(_ content: TabBarContent, frame: CGRect) {
        guard let bar = bars[content.group] else { return }
        apply(content, frame: frame, to: bar)
    }

    /// New content through the model and a new frame on the panel itself, without ordering it.
    private func apply(_ content: TabBarContent, frame: CGRect,
                       to bar: (host: OverlayHost<TabBarView>, model: TabBarModel)) {
        if bar.model.content != content { bar.model.content = content }
        let target = OverlayGeometry.appKitFrame(for: frame, primaryHeight: OverlayGeometry.primaryDisplayHeight)
        if let panel = bar.host.panel, panel.frame != target { panel.setFrame(target, display: true) }
    }

    func reorder(_ group: TabGroupID, above window: WindowID) {
        guard let bar = bars[group], bar.host.isVisible else { return }
        bar.host.order(ordering(above: window))
    }

    func lift(_ group: TabGroupID) {
        // Without window numbers the bars float above every window already.
        guard ordersAboveWindow, let bar = bars[group], bar.host.isVisible else { return }
        bar.host.order(.front)
    }

    func hide(_ group: TabGroupID) {
        bars.removeValue(forKey: group)?.host.hide()
    }

    func hideAll() {
        for bar in bars.values { bar.host.hide() }
        bars = [:]
        ghost.hide()
    }

    func setHidden(_ hidden: Bool) {
        isHidden = hidden
        for bar in bars.values { bar.host.isConcealed = hidden }
    }

    func showGhost(_ tab: TabItem?, at point: CGPoint) {
        guard let tab else { return ghost.hide() }
        let frame = CGRect(x: point.x - TabGeometry.dropGrip.width, y: point.y - Self.ghostSize.height / 2,
                           width: Self.ghostSize.width, height: Self.ghostSize.height)
        ghost.show(TabGhostView(tab: tab), in: frame)
    }

    private func ordering(above window: WindowID) -> OverlayOrdering {
        ordersAboveWindow ? .above(windowNumber: Int(window.rawValue)) : .front
    }

    func makeBar(for group: TabGroupID) -> (host: OverlayHost<TabBarView>, model: TabBarModel) {
        let style = ordersAboveWindow ? OverlayStyle.attached : OverlayStyle(level: .floating, spaces: .own)
        let bar = (host: OverlayHost<TabBarView>(style: style), model: TabBarModel(group: group))
        bar.host.isConcealed = isHidden
        bars[group] = bar
        return bar
    }
}
