import Contracts
import OverlayKit
import SwiftUI

/// The switcher panel: a strip of window cards that keeps the selection in view, with notes
/// underneath. It has a fixed ideal size, so the host can fit the panel to it.
struct SwitcherView: View {
    let model: SwitcherModel
    /// Shared by the cards, so the selection can slide from one card to the next.
    @Namespace private var selection

    var body: some View {
        VStack(spacing: 0) {
            strip
            if !model.notices.isEmpty { notices }
        }
        .fixedSize()
        .surface(.panel(.switcher))
        // Each switcher starts with fresh view state, scrolled to its own selection.
        .id(ObjectIdentifier(model))
    }

    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: SwitcherLayout.cardSpacing) {
                    ForEach(model.items) { item in
                        SwitcherCard(item: item, isSelected: item.id == model.selectedID,
                                     previewHeight: model.previewHeight, selection: selection, actions: model.actions)
                            .id(item.id)
                    }
                }
                .padding(SwitcherLayout.stripPadding)
            }
            .frame(width: model.stripWidth, height: SwitcherLayout.stripHeight(previewHeight: model.previewHeight))
            .onAppear { scrollToTarget(proxy, animated: false) }
            .onChange(of: model.scrollTarget) { scrollToTarget(proxy, animated: true) }
        }
    }

    private var notices: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(model.notices, id: \.self) { notice in
                Label(notice, systemImage: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, SwitcherLayout.stripPadding + 4)
        .padding(.bottom, SwitcherLayout.stripPadding)
        .frame(width: model.stripWidth, alignment: .leading)
    }

    private func scrollToTarget(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let id = model.scrollTarget else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id, anchor: .center) }
        } else {
            proxy.scrollTo(id, anchor: .center)
        }
    }
}

/// One window: hovering selects it, clicking switches to it.
private struct SwitcherCard: View {
    let item: SwitcherItem
    let isSelected: Bool
    let previewHeight: CGFloat
    let selection: Namespace.ID
    let actions: SwitcherModel.Actions

    var body: some View {
        let id = item.id
        ThumbnailCard(window: item.window, icon: AppIconProvider.shared.icon(for: item.window), thumbnail: item.image,
                      isSelected: isSelected, previewHeight: previewHeight, selectionNamespace: selection,
                      onHover: { inside in if inside { actions.hover(id) } })
            .onTapGesture { actions.choose(id) }
    }
}
