import SwiftUI

private struct SettingsPageTitleKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

private extension EnvironmentValues {
    var settingsPageTitle: String? {
        get { self[SettingsPageTitleKey.self] }
        set { self[SettingsPageTitleKey.self] = newValue }
    }
}

public enum SettingsPageLayout {
    public static let windowOuterInset: CGFloat = 2
    public static let windowCornerRadius: CGFloat = 14
    public static let collapsedNavigationWidth: CGFloat = 76
    public static let listWidth: CGFloat = 176
    public static let compactListWidth: CGFloat = 144
    public static let contentInset: CGFloat = 20
    public static let headerHeight: CGFloat = 60
    public static let headerContentSpacing: CGFloat = 0

    /// Preserve room for settings before collapsing the navigation to its icon rail.
    public static func navigationWidth(available: CGFloat) -> CGFloat {
        let width = min(178, max(collapsedNavigationWidth, available - 640))
        return width < 128 ? collapsedNavigationWidth : width
    }
}

/// The App supplies the current page title; modules supply content and, optionally, a list.
/// A page without a list reserves no column or divider. Scrolling stays with each content view.
public struct SettingsPageTemplate<Sidebar: View, Content: View, HeaderActions: View>: View {
    private let sidebar: Sidebar?
    private let content: Content
    private let headerActions: HeaderActions
    @Environment(\.settingsPageTitle) private var title
    @Environment(\.settingsCompactLayout) private var compact

    public init(@ViewBuilder sidebar: () -> Sidebar, @ViewBuilder content: () -> Content,
                @ViewBuilder headerActions: () -> HeaderActions) {
        self.sidebar = sidebar()
        self.content = content()
        self.headerActions = headerActions()
    }

    public init(@ViewBuilder sidebar: () -> Sidebar, @ViewBuilder content: () -> Content) where HeaderActions == EmptyView {
        self.sidebar = sidebar()
        self.content = content()
        self.headerActions = EmptyView()
    }

    public init(@ViewBuilder content: () -> Content) where Sidebar == EmptyView, HeaderActions == EmptyView {
        self.sidebar = nil
        self.content = content()
        self.headerActions = EmptyView()
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let title {
                HStack {
                    Text(title).font(SettingsTypography.pageTitle).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    headerActions
                }
                .padding(.horizontal, SettingsPageLayout.contentInset + 4)
                .frame(height: SettingsPageLayout.headerHeight)
                Divider()
            }
            HStack(spacing: 0) {
                if let sidebar {
                    sidebar.frame(width: compact ? SettingsPageLayout.compactListWidth : SettingsPageLayout.listWidth)
                    Divider()
                }
                content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, title == nil ? 0 : SettingsPageLayout.headerContentSpacing)
            .settingsColumnTransition(compact: compact)
        }
        .settingsPageStyle()
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SettingsColumnTransition: ViewModifier {
    let compact: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : .smooth(duration: 0.28), value: compact)
    }
}

public extension View {
    /// Animate breakpoint changes only; continuous window resizing stays attached to the pointer.
    func settingsColumnTransition(compact: Bool) -> some View {
        modifier(SettingsColumnTransition(compact: compact))
    }

    /// Keeps page identity in the App's navigation while all modules share one layout template.
    func settingsPageTitle(_ title: String) -> some View {
        environment(\.settingsPageTitle, title)
    }
}
