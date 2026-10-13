import Contracts
import OverlayKit
import SwiftUI

/// The leader hint panel, faded while lingering, or a short notice. Sizes itself to its content.
struct LeaderOverlayView: View {
    var overlay: LeaderOverlay

    var body: some View {
        switch overlay {
        case .hints(let hints):
            HintPanelView(options: hints.options, title: hints.title, footer: hints.footer, dimmed: hints.isFaded)
        case .notice(let notice):
            NoticeView(notice: notice)
        }
    }
}

private struct NoticeView: View {
    var notice: LeaderNotice

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = notice.title {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            }
            Label {
                Text(notice.message)
            } icon: {
                SkinSymbol(.warning)
            }
            .font(.system(size: 13))
        }
        // A fixed width lets long reasons wrap instead of stretching the panel across the display.
        .frame(width: 300, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(14)
        .surface(.panel(.notice))
        .accessibilityElement(children: .combine)
    }
}

/// Shows the leader overlay in a pass-through panel, centered in the given area.
@MainActor
final class OverlayLeaderPresenter: LeaderPresenting {
    private let host = OverlayHost<LeaderOverlayView>(style: .hud)

    func show(_ overlay: LeaderOverlay, in area: CGRect) {
        host.show(LeaderOverlayView(overlay: overlay), placement: .centered(in: area))
    }

    func hide() {
        host.hide()
    }
}
