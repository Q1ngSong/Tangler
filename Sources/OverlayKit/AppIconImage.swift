import AppKit
import SwiftUI

/// An application icon at a fixed size, or a generic window symbol when there is none.
struct AppIconImage: View {
    var icon: NSImage?
    var size: CGFloat

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                Image(systemName: "macwindow").font(.system(size: size * 0.7)).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
