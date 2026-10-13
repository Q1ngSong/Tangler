import CoreKit
import AppKit
import Contracts
import Observation
import OverlayKit
import SwiftUI

/// What one bar shows. The panels change it in place, so a new title never rebuilds a panel.
@MainActor
@Observable
final class TabBarModel {
    var content: TabBarContent
    @ObservationIgnored var onAction: @MainActor (TabBarAction) -> Void = { _ in }

    init(group: TabGroupID) {
        content = TabBarContent(group: group, tabs: [], incoming: nil, leaving: nil)
    }
}

/// The strip of tabs above a group's windows (tab groups design 4.3). While something is
/// dragged over it, it shows itself as it would be after the drop (tab drop preview design 4.2).
struct TabBarView: View {
    /// Room left between the bar and the window below it.
    static let gap: CGFloat = 2
    static let inset: CGFloat = 3
    /// The tabs making room and sliding back.
    static let slide = Animation.snappy(duration: 0.18)
    /// The incoming tab and the ring coming and going.
    static let appear = Animation.easeOut(duration: 0.12)

    let model: TabBarModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A tab from outside has no controls. One of the bar's own tabs keeps its chip, with its
    /// controls, while it moves.
    static func isPlaceholder(_ slot: TabBarArrangement.Slot) -> Bool { slot.kind == .incoming }

    var body: some View {
        GeometryReader { proxy in
            let content = model.content
            let arrangement = TabBarArrangement(tabs: content.tabs, incoming: content.incoming, leaving: content.leaving)
            let layout = TabBarLayout(barWidth: proxy.size.width, count: arrangement.slots.count)
            let height = max(0, proxy.size.height - Self.inset * 2)
            ZStack(alignment: .topLeading) {
                ForEach(Array(arrangement.slots.enumerated()), id: \.element.id) { index, slot in
                    chip(slot, group: content.group, showsTitle: layout.showsTitles)
                        .frame(width: layout.tabWidth, height: height)
                        .offset(x: layout.minX(ofTab: index), y: Self.inset)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .animation(reduceMotion ? nil : Self.slide, value: arrangement.order)
            .overlay {
                Color.clear.surface(.dropTarget(.tabBar))
                    .opacity(arrangement.isJoining ? 1 : 0)
                    .animation(reduceMotion ? nil : Self.appear, value: arrangement.isJoining)
                    .allowsHitTesting(false)
            }
        }
        .surface(.panel(.tabBar))
        .padding(.bottom, Self.gap)
    }

    @ViewBuilder
    private func chip(_ slot: TabBarArrangement.Slot, group: TabGroupID, showsTitle: Bool) -> some View {
        if Self.isPlaceholder(slot) {
            IncomingTabChip(tab: slot.tab, showsTitle: showsTitle)
        } else {
            TabChip(tab: slot.tab, group: group, showsTitle: showsTitle, isMoving: slot.kind == .moving,
                    isFaded: slot.isFaded, onAction: model.onAction)
        }
    }
}

/// One tab: icon, title and, on hover or when active, ×. Click to switch, drag to move,
/// right-click for the rest.
struct TabChip: View {
    let tab: TabItem
    let group: TabGroupID
    let showsTitle: Bool
    /// Dragged to another slot of its own bar: drawn as an incoming tab.
    var isMoving = false
    /// Dragged away from its bar.
    var isFaded = false
    let onAction: @MainActor (TabBarAction) -> Void
    @State private var hovering = false

    /// ⌘ and nothing else, as for dragging a window onto a bar; fn and caps lock do not count.
    static var commandAlone: Bool {
        NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.function, .capsLock, .numericPad]) == .command
    }

    /// Dragged away from its bar it is fainter than a hidden app's tab.
    static func opacity(of tab: TabItem, isFaded: Bool) -> Double { isFaded ? 0.35 : tab.isHidden ? 0.5 : 1 }

    var body: some View {
        HStack(spacing: 6) {
            TabIcon(tab: tab, size: 16)
            if showsTitle {
                Text(tab.label)
                    .font(.system(size: 12, weight: tab.isActive ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if hovering || tab.isActive {
                    Button { onAction(.close(tab.id)) } label: { Image(systemName: "xmark") }
                        .buttonStyle(.overlayControl(.tabClose))
                        .help(L10n.text("overlaykit.close.window"))
                        .accessibilityLabel(L10n.text("tabgroups.close", String(describing: (tab.label))))
                }
            }
        }
        .padding(.horizontal, showsTitle ? 8 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: showsTitle ? .leading : .center)
        .surface(.tab(state))
        .opacity(Self.opacity(of: tab, isFaded: isFaded))
        .contentShape(Rectangle())
        .onOverlayHover { hovering = $0 }
        .onTapGesture { onAction(.select(tab.id)) }
        .gesture(DragGesture(minimumDistance: 6)
            .onChanged { _ in onAction(.drag(tab.id, OverlayGeometry.mouseLocation, command: Self.commandAlone)) }
            .onEnded { _ in onAction(.drop(tab.id, OverlayGeometry.mouseLocation, command: Self.commandAlone)) })
        .contextMenu {
            Button(L10n.text("tabgroups.remove.from.tab.group")) { onAction(.remove(tab.id)) }
            Button(L10n.text("overlaykit.close.window")) { onAction(.close(tab.id)) }
            Divider()
            Button(L10n.text("tabgroups.ungroup.windows")) { onAction(.ungroup(group)) }
        }
        .help(tab.label)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(tab.isActive ? [.isButton, .isSelected] : .isButton)
    }

    private var state: TabState {
        if isMoving { return .incoming }
        if tab.isActive { return .active }
        return hovering ? .hover : .rest
    }
}

/// The tab a window or tab from outside would become: no controls, it is only shown.
struct IncomingTabChip: View {
    let tab: TabItem
    let showsTitle: Bool

    var body: some View {
        HStack(spacing: 6) {
            TabIcon(tab: tab, size: 16)
            if showsTitle {
                Text(tab.label)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, showsTitle ? 8 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: showsTitle ? .leading : .center)
        .surface(.tab(.incoming))
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.text("tabgroups.will.join", String(describing: (tab.label))))
    }
}

/// The app's icon, or a window symbol when there is none.
struct TabIcon: View {
    let tab: TabItem
    let size: CGFloat

    var body: some View {
        Group {
            if let image = AppIconProvider.shared.icon(pid: tab.pid, bundleID: tab.bundleID) {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Image(systemName: "macwindow").font(.system(size: size * 0.75)).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The tab under the pointer once it is dragged out of its bar.
struct TabGhostView: View {
    let tab: TabItem

    var body: some View {
        HStack(spacing: 6) {
            TabIcon(tab: tab, size: 16)
            Text(tab.label).font(.system(size: 12)).lineLimit(1).truncationMode(.tail)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .surface(.panel(.tabGhost))
    }
}
