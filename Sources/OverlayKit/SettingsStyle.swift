import SwiftUI

/// Settings typography is shared by native forms and custom pages such as Workspaces.
/// Miniature app illustrations keep their own scaled text; these roles describe the settings UI.
public enum SettingsTypography {
    public static let brand: Font = .system(size: 12, weight: .semibold)
    public static let sidebarItem: Font = .system(size: 12)
    public static let sidebarSection: Font = .system(size: 10)
    public static let pageTitle: Font = .system(size: 20, weight: .semibold)
    public static let sectionTitle: Font = .system(size: 13, weight: .semibold)
    public static let body: Font = .system(size: 13)
    public static let caption: Font = .system(size: 11)
}

public extension View {
    /// One baseline for settings text and controls, including pages that do not use Form.
    func settingsPageStyle() -> some View {
        font(SettingsTypography.body)
            .controlSize(.regular)
            .scrollContentBackground(.hidden)
    }

    /// The common page template, with no list column, for native grouped forms.
    func settingsFormStyle() -> some View {
        SettingsPageTemplate { formStyle(.grouped) }
    }

    /// The grouped surface for custom settings content that cannot live in a native Form row.
    func settingsGroupSurface() -> some View {
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
        return background(Color(nsColor: .controlBackgroundColor).opacity(0.65), in: shape)
            .overlay(shape.strokeBorder(.primary.opacity(0.07), lineWidth: 0.5))
            .clipShape(shape)
    }
}

private struct SettingsCompactLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// Set by the settings shell from the space left after navigation.
    var settingsCompactLayout: Bool {
        get { self[SettingsCompactLayoutKey.self] }
        set { self[SettingsCompactLayoutKey.self] = newValue }
    }
}
