import AppKit
import SwiftUI

/// The look before the reskin, frozen: the literal values of tangler e8c0a59, copied as they
/// were (Liquid Glass skin design 3.4). SkinTests pins every value, so nobody changes classic
/// by accident. Deleting this file retires the switch (design 8.2).
enum ClassicSkin {
    static let zones = ZoneStyles(zone: ZoneStyle(cornerRadius: 12, fillOpacity: 0.2, strokeOpacity: 0.9, lineWidth: 3),
                                  gridCell: ZoneStyle(cornerRadius: 8, fillOpacity: 0.06, strokeOpacity: 0.35, lineWidth: 1))

    static func panelRadius(_ kind: PanelKind) -> CGFloat {
        switch kind {
        case .switcher: 24
        case .palette: 20
        case .dockPreview, .hints, .notice: 18
        case .toast, .report: 16
        case .tabBar: 10
        case .tabGhost: 8
        }
    }

    /// The whole hint panel, glass included, while lingering (LeaderOverlayView).
    static let hintsDimmedOpacity = 0.5
    static let cardRadius: CGFloat = 14
    static func cardFill(_ state: CardState) -> Double {
        switch state {
        case .selected: 0.14
        case .hover: 0.06
        case .rest: 0
        }
    }
    static let cardSelectedStroke = 0.28
    static let cardStrokeWidth: CGFloat = 1
    static let wellRadius: CGFloat = 8
    static let wellFill = 0.06
    /// The search band's separator, under the field.
    static let fieldDividerHeight: CGFloat = 1
    static let selectionOpacity = 0.25
    static let selectionRadius: CGFloat = 10
    static func chipRadius(_ size: ChipSize) -> CGFloat { size == .regular ? 6 : 5 }
    static let chipFill = 0.1
    static let chipStroke = 0.15
    static let chipStrokeWidth: CGFloat = 0.5
    static let labelRadius: CGFloat = 14
    static let labelBackground = 0.8
    static let scrimOpacity = 0.12
    static let tabRadius: CGFloat = 7
    static func tabFill(_ state: TabState) -> Double {
        switch state {
        case .active: 0.16
        case .hover: 0.08
        case .rest, .incoming: 0
        }
    }
    // Added with the tab drop preview (2026-10-10); classic had no such element before.
    static let tabIncomingFill = 0.14
    static let tabIncomingStrokeWidth: CGFloat = 1
    static let tabIncomingDash: [CGFloat] = [4, 3]
    static let dropRingWidth: CGFloat = 2
    static let controlFontSize: CGFloat = 9
    static let cardControlSide: CGFloat = 18
    static let cardControlFill = 0.12
    static let tabCloseSide: CGFloat = 16

    @ViewBuilder
    static func paint<V: View>(_ content: V, as role: SurfaceRole) -> some View {
        switch role {
        case .panel(.hints(let dimmed)):
            // LeaderOverlayView faded the whole panel, glass included.
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: panelRadius(.hints(dimmed: dimmed)), style: .continuous))
                .opacity(dimmed ? hintsDimmedOpacity : 1)
                .animation(.easeOut(duration: 0.15), value: dimmed)
        case .panel(let kind):
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: panelRadius(kind), style: .continuous))
        case .card(let state, _):
            let shape = RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
            content
                .background(shape.fill(Color.primary.opacity(cardFill(state))))
                .overlay(shape.strokeBorder(Color.primary.opacity(state == .selected ? cardSelectedStroke : 0),
                                            lineWidth: cardStrokeWidth))
                .contentShape(shape)
                .animation(.easeOut(duration: 0.12), value: state == .selected)
        case .well:
            let shape = RoundedRectangle(cornerRadius: wellRadius, style: .continuous)
            content.background(shape.fill(Color.primary.opacity(wellFill))).clipShape(shape)
        case .field(let band):
            VStack(spacing: 0) {
                content.frame(height: band - fieldDividerHeight)
                Divider()
            }
        case .results:
            content
        case .selection(let on):
            content.background(on ? Color.accentColor.opacity(selectionOpacity) : Color.clear,
                               in: RoundedRectangle(cornerRadius: selectionRadius, style: .continuous))
        case .chip(let size):
            let shape = RoundedRectangle(cornerRadius: chipRadius(size), style: .continuous)
            content
                .background(shape.fill(Color.primary.opacity(chipFill)))
                .overlay(shape.strokeBorder(Color.primary.opacity(chipStroke), lineWidth: chipStrokeWidth))
        case .label:
            content.foregroundStyle(.white)
                .background(RoundedRectangle(cornerRadius: labelRadius, style: .continuous).fill(.black.opacity(labelBackground)))
        case .scrim:
            content.background(Color.black.opacity(scrimOpacity))
        case .tab(.incoming):
            let shape = RoundedRectangle(cornerRadius: tabRadius, style: .continuous)
            content.background(shape.fill(Color.accentColor.opacity(tabIncomingFill)))
                .overlay(shape.strokeBorder(Color.accentColor,
                                            style: StrokeStyle(lineWidth: tabIncomingStrokeWidth, dash: tabIncomingDash)))
        case .dropTarget(let kind):
            content.overlay(RoundedRectangle(cornerRadius: panelRadius(kind), style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: dropRingWidth))
        case .tab(let state):
            content.background(RoundedRectangle(cornerRadius: tabRadius, style: .continuous)
                .fill(state == .rest ? Color.clear : Color.primary.opacity(tabFill(state))))
        }
    }

    /// The buttons of ThumbnailCard and TabChip at e8c0a59, moved here as they were.
    @ViewBuilder
    static func control(_ kind: OverlayControlKind, _ configuration: PrimitiveButtonStyleConfiguration) -> some View {
        switch kind {
        case .card:
            Button(action: configuration.trigger) {
                configuration.label
                    .font(.system(size: controlFontSize, weight: .bold))
                    .frame(width: cardControlSide, height: cardControlSide)
                    .background(Circle().fill(Color.primary.opacity(cardControlFill)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        case .tabClose:
            Button(action: configuration.trigger) {
                configuration.label
                    .font(.system(size: controlFontSize, weight: .bold))
                    .frame(width: tabCloseSide, height: tabCloseSide)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
