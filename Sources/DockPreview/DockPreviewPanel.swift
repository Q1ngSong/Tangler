import AppKit
import CoreGraphics
import OverlayKit

/// The preview in an overlay panel beside the Dock icon, clickable without taking focus.
///
/// Animated, it appears the way a popover does: a quick fade while sliding a few points out
/// of the Dock, glides from icon to icon, and fades out. With Reduce Motion it only fades.
@MainActor
final class DockPreviewPanel: DockPreviewPresenting {
    private static let appearDuration: TimeInterval = 0.18
    private static let moveDuration: TimeInterval = 0.15
    private static let hideDuration: TimeInterval = 0.12
    private static let slide: CGFloat = 10

    var animates = true
    private let host = OverlayHost<DockPreviewView>(style: .interactive)
    /// Bumped by every show and hide, so a fade-out that ends after a newer show leaves the panel up.
    private var generation = 0

    func show(_ content: DockPreviewContent, placement: OverlayPlacement, actions: DockPreviewActions) -> CGRect {
        generation += 1
        // The layout knows the exact size, so nothing needs measuring.
        let frame = placement.frame(for: content.layout.panelSize)
        let view = DockPreviewView(content: content, actions: actions)
        guard animates else {
            host.show(view, in: frame)
            host.panel?.alphaValue = 1
            return frame
        }
        if host.isVisible, let panel = host.panel {
            // Already up, or fading out: take the new content and glide to the new icon.
            host.update(view)
            animate(Self.moveDuration) {
                panel.animator().setFrame(Self.appKit(frame), display: true)
                panel.animator().alphaValue = 1
            }
        } else {
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            let start = reduceMotion ? frame
                : DockPreviewMotion.startFrame(for: frame, dockEdge: content.item.dockEdge, distance: Self.slide)
            host.show(view, in: start)
            guard let panel = host.panel else { return frame }
            panel.alphaValue = 0
            animate(Self.appearDuration) {
                panel.animator().setFrame(Self.appKit(frame), display: true)
                panel.animator().alphaValue = 1
            }
        }
        return frame
    }

    func hide() {
        generation += 1
        guard animates, host.isVisible, let panel = host.panel else { return host.hide() }
        let generation = self.generation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.hideDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == generation else { return }
                self.host.hide()
                self.host.panel?.alphaValue = 1
            }
        })
    }

    private func animate(_ duration: TimeInterval, _ changes: () -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            changes()
        }
    }

    private static func appKit(_ frame: CGRect) -> CGRect {
        OverlayGeometry.appKitFrame(for: frame, primaryHeight: OverlayGeometry.primaryDisplayHeight)
    }
}
