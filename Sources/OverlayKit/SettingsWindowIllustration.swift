import CoreKit
import SwiftUI

/// A preview window, showing an app identity or a synthetic document.
/// No window capture or application launch is involved.
public struct SettingsWindowIllustration: View {
    public enum ContentStyle { case document, appIdentity }

    private let title: String
    private let bundleID: String?
    private let variant: Int
    private let contentStyle: ContentStyle

    public init(title: String, bundleID: String?, variant: Int = 0, contentStyle: ContentStyle = .document) {
        self.title = title
        self.bundleID = bundleID
        self.variant = variant
        self.contentStyle = contentStyle
    }

    public var body: some View {
        GeometryReader { room in
            if contentStyle == .appIdentity {
                identity(in: room.size)
            } else if room.size.width < 70 || room.size.height < 45 {
                icon.resizable().scaledToFit()
                    .frame(width: min(26, room.size.width * 0.55), height: min(26, room.size.height * 0.55))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 3) {
                        ForEach([Color.red, .yellow, .green], id: \.self) { color in
                            Circle().fill(color.opacity(0.8)).frame(width: 4, height: 4)
                        }
                        Color.clear.frame(width: 4)
                        icon.resizable().scaledToFit().frame(width: 10, height: 10)
                        Text(title).font(.system(size: 8, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 3)
                    }
                    .padding(.horizontal, 7).frame(height: 21)
                    .background(.white.opacity(0.1))
                    content(availableWidth: room.size.width - 16).padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(.background.opacity(0.72))
                }
                .frame(width: room.size.width, height: room.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .accessibilityHidden(true)
    }

    /// Saved workspaces identify the real window instead of inventing document contents.
    private func identity(in size: CGSize) -> some View {
        let showsTitle = size.width >= 32 && size.height >= 30
        let iconSize = max(0, min(32, size.width - 12, size.height * 0.38, size.height - (showsTitle ? 26 : 8)))
        return VStack(spacing: 5) {
            icon.resizable().scaledToFit().frame(width: iconSize, height: iconSize)
            if showsTitle {
                Text(title).font(.system(size: 10, weight: .medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(size.height >= 72 ? 2 : 1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private var icon: Image {
        if let icon = AppIconProvider.shared.icon(pid: nil, bundleID: bundleID) { return Image(nsImage: icon) }
        return Image(systemName: "macwindow")
    }

    @ViewBuilder private func content(availableWidth: CGFloat) -> some View {
        if bundleID == "com.apple.finder" {
            HStack(spacing: 7) {
                VStack(alignment: .leading, spacing: 5) {
                    Image(systemName: "sidebar.left").foregroundStyle(.secondary)
                    line(18)
                    line(14)
                }.frame(width: 22)
                // A small switcher tile has room for fewer folders than a full preview.
                ForEach(0..<max(1, min(3, Int((availableWidth - 22) / 26))), id: \.self) { _ in
                    VStack(spacing: 5) {
                        Image(systemName: variant == 0 ? "folder.fill" : "doc.fill").font(.system(size: 17)).foregroundStyle(.blue.gradient)
                        line(19)
                    }.frame(maxWidth: .infinity)
                }
            }
        } else if bundleID == "com.apple.Safari" {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill").font(.system(size: 5))
                    Text(variant == 0 ? "tangler.app" : "tangler.app/guide").font(.system(size: 7))
                }
                .foregroundStyle(.secondary).frame(maxWidth: .infinity)
                .padding(3).background(.primary.opacity(0.035), in: Capsule())
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: variant == 0 ? "rectangle.3.group" : "book.closed").font(.system(size: 18)).frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        line(42, accent: true)
                        line(56)
                        line(35)
                    }.padding(.top, 2)
                }
            }
        } else if bundleID == "com.microsoft.VSCode" {
            VStack(alignment: .leading, spacing: 5) {
                Text(variant == 0 ? "struct Workspace {" : "<main class=\"glass\">")
                    .font(.system(size: 8, design: .monospaced)).foregroundStyle(.indigo).lineLimit(1)
                line(64, accent: true).padding(.leading, 10)
                line(82).padding(.leading, 10)
                line(50, accent: true).padding(.leading, 10)
                Text(variant == 0 ? "}" : "</main>").font(.system(size: 8, design: .monospaced)).foregroundStyle(.indigo)
            }
        } else {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(bundleID == "com.apple.Notes" ? L10n.text("overlaykit.ideas.and.plans") : L10n.text("overlaykit.design.draft"))
                        .font(.system(size: 9, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                line(68, accent: true)
                line(86)
                line(75)
                line(49)
            }
        }
    }

    private func line(_ width: CGFloat, accent: Bool = false) -> some View {
        Capsule().fill(accent ? Color.accentColor.opacity(0.38) : Color.primary.opacity(0.12))
            .frame(maxWidth: width).frame(height: 2.5)
    }
}
