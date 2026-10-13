import CoreKit
import OverlayKit
import SwiftUI

/// One palette row: icon, name, what it is, and for a command its current leader keys.
struct PaletteRowView: View {
    let item: PaletteItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            icon.frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                if let subtitle = item.subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if !item.keys.isEmpty {
                PaletteKeyCaps(keys: item.keys).accessibilityLabel(L10n.text("commandpalette.leader", String(describing: (item.keys.joined(separator: " ")))))
            }
            if let shortcut = item.shortcut {
                PaletteKeyCaps(keys: [shortcut]).accessibilityLabel(L10n.text("commandpalette.shortcut", String(describing: (shortcut))))
            }
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        .surface(.selection(isSelected))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var icon: some View {
        switch item.kind {
        case .window(let window):
            if let image = AppIconProvider.shared.icon(for: window) {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Image(systemName: "macwindow").foregroundStyle(.secondary)
            }
        case .command:
            Image(systemName: "command").font(.system(size: 14)).foregroundStyle(.secondary)
        case .dynamic:
            Image(systemName: "square.stack.3d.up").font(.system(size: 14)).foregroundStyle(.secondary)
        }
    }
}

/// Keys drawn as small key caps, the same ones the leader hint panel uses.
struct PaletteKeyCaps: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                KeyCap(key, size: .small)
            }
        }
    }
}
