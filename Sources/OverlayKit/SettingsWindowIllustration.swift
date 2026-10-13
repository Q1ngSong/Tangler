import CoreKit
import SwiftUI

/// A small synthetic document, using only an installed app's icon and illustrative content.
/// No window capture or application launch is involved.
public struct SettingsWindowIllustration: View {
    private let title: String
    private let bundleID: String?

    public init(title: String, bundleID: String?) {
        self.title = title
        self.bundleID = bundleID
    }

    public var body: some View {
        GeometryReader { room in
            if room.size.width < 70 || room.size.height < 45 {
                icon.resizable().scaledToFit()
                    .frame(width: min(26, room.size.width * 0.55), height: min(26, room.size.height * 0.55))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 3) {
                        ForEach([Color.red, .yellow, .green], id: \.self) { color in
                            Circle().fill(color.opacity(0.8)).frame(width: 4, height: 4)
                        }
                        Spacer(minLength: 3)
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
                        Image(systemName: "folder.fill").font(.system(size: 17)).foregroundStyle(.blue.gradient)
                        line(19)
                    }.frame(maxWidth: .infinity)
                }
            }
        } else if bundleID == "com.apple.Safari" {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill").font(.system(size: 5))
                    Text("apple.com").font(.system(size: 7))
                }
                .foregroundStyle(.secondary).frame(maxWidth: .infinity)
                .padding(3).background(.primary.opacity(0.035), in: Capsule())
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "apple.logo").font(.system(size: 18)).frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        line(42, accent: true)
                        line(56)
                        line(35)
                    }.padding(.top, 2)
                }
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
