import CoreKit
import SwiftUI

/// Gives an overlay the skin the user chose. It reads `CurrentSkin.shared` in its body, so a
/// panel on screen redraws when the skin changes. A `.environment(\.skin, …)` inside the content
/// still wins, which is how the gallery picks a skin.
struct SkinnedRoot<Content: View>: View {
    let content: Content

    var body: some View {
        content.environment(\.skin, CurrentSkin.shared.value)
            .environment(\.locale, L10n.current.locale)
    }
}
