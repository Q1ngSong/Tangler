import CoreKit
import Contracts
import SwiftUI

/// What the picker draws on one display: a dimmed screen, the window under the pointer
/// highlighted, and a prompt at the top.
struct WindowPickerOverlay: View {
    let model: WindowPickerModel
    /// The display, in global coordinates.
    let canvas: CGRect
    let prompt: String

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear.surface(.scrim)
            HighlightLayer(target: model.candidate?.frame, canvas: canvas)
            Text(Self.message(prompt: prompt, candidate: model.candidate))
                .font(.system(size: 14, weight: .medium))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .surface(.label)
                .padding(.top, 60)
        }
        .frame(width: canvas.width, height: canvas.height)
    }

    static func message(prompt: String, candidate: WindowInfo?) -> String {
        guard let window = candidate else { return L10n.text("overlaykit.esc.to.cancel", String(describing: (prompt))) }
        let name = window.title.isEmpty ? window.appName : "\(window.appName) · \(window.title)"
        return L10n.text("overlaykit.nclick.to.select.esc.to.cancel", String(describing: (name)))
    }
}
