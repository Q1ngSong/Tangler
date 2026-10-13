import SwiftUI

/// A bounded settings canvas for saved layouts and illustrative desktops.
public struct SettingsPreview<Content: View>: View {
    private let title: String
    private let content: Content
    private let aspectRatio: CGFloat?
    private let maxWidth: CGFloat

    public init(_ title: String, aspectRatio: CGFloat? = nil, maxWidth: CGFloat = .infinity, @ViewBuilder content: () -> Content) {
        self.title = title
        self.aspectRatio = aspectRatio
        self.maxWidth = maxWidth
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(SettingsTypography.sectionTitle)
            canvas
                .frame(maxWidth: maxWidth)
                .background { SettingsPreviewBackdrop() }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.35), lineWidth: 0.7))
                .accessibilityLabel(title)
        }
        .frame(maxWidth: maxWidth)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 6)
    }

    @ViewBuilder private var canvas: some View {
        if let aspectRatio {
            GeometryReader { room in
                content.frame(width: room.size.width, height: room.size.height)
            }.aspectRatio(aspectRatio, contentMode: .fit)
        } else {
            content.frame(maxWidth: .infinity).frame(height: 176)
        }
    }
}
