import AppKit
import Contracts
import OverlayKit
import SwiftUI

/// One app's windows as cards on Liquid Glass, in a row or a column along the Dock. Every
/// size comes from `DockPreviewLayout`, so the view fills exactly the frame it was placed in.
struct DockPreviewView: View {
    let content: DockPreviewContent
    let actions: DockPreviewActions

    private var layout: DockPreviewLayout { content.layout }

    var body: some View {
        VStack(spacing: DockPreviewLayout.spacing) {
            strip.frame(width: layout.stripSize.width, height: layout.stripSize.height)
            ForEach(content.notices, id: \.self) { notice in
                Text(notice)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: layout.stripSize.width, height: DockPreviewLayout.noticeHeight)
            }
        }
        .padding(DockPreviewLayout.padding)
        .frame(width: layout.panelSize.width, height: layout.panelSize.height)
        .surface(.panel(.dockPreview))
    }

    @ViewBuilder
    private var strip: some View {
        if layout.scrolls {
            ScrollView(layout.axis == .horizontal ? .horizontal : .vertical, showsIndicators: false) { cards }
        } else {
            cards
        }
    }

    private var cards: some View {
        let stack = layout.axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: DockPreviewLayout.spacing))
            : AnyLayout(VStackLayout(spacing: DockPreviewLayout.spacing))
        let icon = AppIconProvider.shared.icon(for: content.item)
        return stack {
            ForEach(content.cards) { card in
                ThumbnailCard(window: card.window, icon: icon, thumbnail: card.thumbnail, isSelected: false,
                              previewHeight: DockPreviewLayout.previewHeight,
                              onClose: { actions.close(card.id) },
                              onMinimize: card.window.isMinimized ? nil : { actions.minimize(card.id) })
                    .frame(width: card.size.width, height: card.size.height)
                    .opacity(card.window.isMinimized ? 0.65 : 1)
                    .onTapGesture { actions.choose(card.id) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { actions.choose(card.id) }
            }
        }
    }
}
