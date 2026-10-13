import CoreKit
import Observation
import SwiftUI

/// How Tangler draws its own interface (Liquid Glass skin design 3.2). Stored in the App's
/// settings, so the raw values are a file format and must not be renamed.
public enum Skin: String, Codable, CaseIterable, Sendable {
    /// macOS 26 Liquid Glass: one glass per overlay with flat fills inside, concentric corners,
    /// grouped glass.
    case liquidGlass
    /// The look before the reskin (tangler e8c0a59): only the overlay's shell is glass.
    case classic

    public var title: String { self == .liquidGlass ? L10n.text("overlaykit.liquid.glass") : L10n.text("overlaykit.classic") }
}

// Command Line Tools have no SwiftUIMacros plugin, so no @Entry: the key is written out.
private struct SkinKey: EnvironmentKey {
    static let defaultValue: Skin = .liquidGlass
}

public extension EnvironmentValues {
    /// The skin roles paint with. Feature modules never read it; they name roles instead.
    var skin: Skin {
        get { self[SkinKey.self] }
        set { self[SkinKey.self] = newValue }
    }
}

/// The skin the user chose. The App writes it at launch and from the settings; overlays read it
/// in `SkinnedRoot`'s body, so Observation redraws the panels on screen when it changes.
@MainActor
@Observable
public final class CurrentSkin {
    public static let shared = CurrentSkin()

    public var value: Skin = .liquidGlass

    /// Tests make their own instance instead of touching `shared`.
    public init() {}
}
