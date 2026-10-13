import SwiftUI

/// A key drawn as a key cap, e.g. "←" or "空格". The size sets the metrics; the skin paints it.
public struct KeyCap: View {
    private let label: String
    private let size: ChipSize

    public init(_ label: String, size: ChipSize = .regular) {
        self.label = label
        self.size = size
    }

    public var body: some View {
        let regular = size == .regular
        Text(label)
            .font(.system(size: regular ? 12 : 11, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .frame(minWidth: regular ? 18 : 16)
            .padding(.horizontal, regular ? 6 : 5)
            .padding(.vertical, regular ? 3 : 2)
            .surface(.chip(size))
    }
}

/// An icon whose glyph the skin decides. Both skins measure the same: Liquid Glass keeps the
/// classic glyph hidden as a placeholder and draws its own over it.
public struct SkinSymbol: View {
    public enum Name: Hashable, Sendable {
        /// Something went wrong, e.g. in the leader's notice.
        case warning
    }

    private let name: Name
    @Environment(\.skin) private var skin

    public init(_ name: Name) {
        self.name = name
    }

    public var body: some View {
        switch skin {
        case .classic:
            Image(systemName: "exclamationmark.circle")
        case .liquidGlass:
            Image(systemName: "exclamationmark.circle")
                .hidden()
                .overlay {
                    Image(systemName: "exclamationmark.triangle.fill").symbolRenderingMode(.multicolor)
                }
        }
    }
}

/// What a page shows when it has nothing to show. Settings only; settings are outside the
/// geometry tests, so the skins may size it differently.
public struct EmptyState: View {
    private let title: String
    private let systemImage: String
    @Environment(\.skin) private var skin

    public init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    public var body: some View {
        switch skin {
        case .classic:
            Text(title).foregroundStyle(.secondary)
        case .liquidGlass:
            ContentUnavailableView(title, systemImage: systemImage)
        }
    }
}
