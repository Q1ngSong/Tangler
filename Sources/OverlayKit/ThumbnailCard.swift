import CoreKit
import AppKit
import Contracts
import SwiftUI

/// A window as the switcher and the Dock previews show it: app icon and title above a
/// thumbnail. Without a thumbnail (no Screen Recording permission) the preview area shows
/// the app icon instead. Hovering shows the minimize and close buttons that have callbacks,
/// at the right of the header, away from the thumbnail.
public struct ThumbnailCard: View {
    private typealias Layout = ThumbnailCardLayout

    private let title: String
    private let icon: NSImage?
    private let thumbnail: CGImage?
    private let isSelected: Bool
    private let windowSize: CGSize?
    private let previewHeight: CGFloat
    private let selectionNamespace: Namespace.ID?
    private let onClose: (() -> Void)?
    private let onMinimize: (() -> Void)?
    private let onHover: ((Bool) -> Void)?
    @State private var isHovering = false

    /// `windowSize` gives the preview the window's shape, also while there is no thumbnail.
    /// Cards sharing a `selectionNamespace` let the selection slide from one card to the next.
    public init(title: String, icon: NSImage?, thumbnail: CGImage?, isSelected: Bool, windowSize: CGSize? = nil,
                previewHeight: CGFloat = ThumbnailCardLayout.defaultPreviewHeight, selectionNamespace: Namespace.ID? = nil,
                onClose: (() -> Void)? = nil, onMinimize: (() -> Void)? = nil, onHover: ((Bool) -> Void)? = nil) {
        self.title = title
        self.icon = icon
        self.thumbnail = thumbnail
        self.isSelected = isSelected
        self.windowSize = windowSize
        self.previewHeight = previewHeight
        self.selectionNamespace = selectionNamespace
        self.onClose = onClose
        self.onMinimize = onMinimize
        self.onHover = onHover
    }

    public init(window: WindowInfo, icon: NSImage?, thumbnail: CGImage?, isSelected: Bool,
                previewHeight: CGFloat = ThumbnailCardLayout.defaultPreviewHeight, selectionNamespace: Namespace.ID? = nil,
                onClose: (() -> Void)? = nil, onMinimize: (() -> Void)? = nil, onHover: ((Bool) -> Void)? = nil) {
        self.init(title: ThumbnailCardLayout.title(for: window), icon: icon, thumbnail: thumbnail,
                  isSelected: isSelected, windowSize: window.frame.size, previewHeight: previewHeight,
                  selectionNamespace: selectionNamespace, onClose: onClose, onMinimize: onMinimize, onHover: onHover)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Layout.spacing) {
            header
            preview
        }
        .frame(width: Layout.previewWidth(for: windowSize, previewHeight: previewHeight))
        .padding(Layout.padding)
        .surface(.card(state, slide: selectionNamespace))
        .background(HoverTracker { hovering in
            isHovering = hovering
            onHover?(hovering)
        })
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var state: CardState {
        isSelected ? .selected : isHovering ? .hover : .rest
    }

    private var header: some View {
        HStack(spacing: 6) {
            AppIconImage(icon: icon, size: 16)
            Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
            if isHovering && (onClose != nil || onMinimize != nil) { controls }
        }
        .frame(height: Layout.headerHeight)
    }

    private var preview: some View {
        ZStack {
            if let thumbnail {
                Image(decorative: thumbnail, scale: 1).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                AppIconImage(icon: icon, size: 48)
            }
        }
        .frame(width: Layout.previewWidth(for: windowSize, previewHeight: previewHeight), height: previewHeight)
        .surface(.well)
    }

    private var controls: some View {
        HStack(spacing: 2) {
            if let onMinimize { controlButton("minus", label: L10n.text("overlaykit.minimize.window"), action: onMinimize) }
            if let onClose { controlButton("xmark", label: L10n.text("overlaykit.close.window"), action: onClose) }
        }
    }

    private func controlButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.overlayControl(.card))
            .help(label)
            .accessibilityLabel("\(label) \(title)")
    }
}
