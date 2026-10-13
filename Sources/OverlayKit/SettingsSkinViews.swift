import CoreKit
import AppKit
import SwiftUI

/// Untinted navigation glass; the shared settings shell owns the window's outer inset.
public struct SettingsSidebarBackground: View {
    @Environment(\.skin) private var skin

    public init() {}

    public var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: SettingsPageLayout.windowCornerRadius,
                                           bottomLeadingRadius: SettingsPageLayout.windowCornerRadius)
        Group {
            if skin == .liquidGlass {
                Color.clear.glassEffect(.regular, in: shape)
            } else {
                shape.fill(.ultraThinMaterial)
            }
        }
    }
}


/// The preview's own wallpaper: continuous blue/violet folds with fine illuminated edges.
/// These are vectors, so a narrow settings window keeps the same sharp contours.
struct SettingsPreviewBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.skin) private var skin
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { room in
            ZStack {
                if skin == .liquidGlass {
                    LinearGradient(colors: [color(0x4B75C9), color(0x7798DD), color(0x8582CC)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    RadialGradient(colors: [color(0xB3A7FF), .clear], center: UnitPoint(x: 0.83, y: 0.1),
                                   startRadius: 0, endRadius: room.size.width * 0.55)
                    RadialGradient(colors: [color(0x506BB9), .clear], center: UnitPoint(x: 0.18, y: 0.9),
                                   startRadius: 0, endRadius: room.size.width * 0.7)
                    PhaseAnimator(reduceMotion ? [0.0] : [0.0, 1.0]) { phase in
                        ZStack {
                        SettingsPreviewFold(phase: 1 - phase)
                            .fill(LinearGradient(colors: [color(0xA6BFFF), color(0x8170CB).opacity(0.4)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .overlay(SettingsPreviewFold(phase: 1 - phase).stroke(.white.opacity(0.55), lineWidth: 0.8))
                            .rotationEffect(.degrees(180)).scaleEffect(1.5).offset(x: room.size.width * 0.12, y: -room.size.height * 0.2)
                        SettingsPreviewFold(phase: phase)
                            .fill(LinearGradient(stops: [
                                .init(color: color(0xF4EAFF), location: 0),
                                .init(color: color(0x95D9FC), location: 0.42),
                                .init(color: color(0x7180CB), location: 1)
                            ], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .overlay {
                                SettingsPreviewFold(phase: phase)
                                    .stroke(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.3),
                                                                   color(0xD5F6FF).opacity(0.8)],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                                            lineWidth: 1)
                            }
                            .shadow(color: .white.opacity(0.55), radius: 5, y: -3)
                            .shadow(color: color(0x303E91).opacity(0.32), radius: 9, y: 8)
                        }
                    } animation: { _ in .easeInOut(duration: 5) }
                } else {
                    LinearGradient(colors: [color(0xDCE3EF), color(0xAAB8D0)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                if colorScheme == .dark { Color(red: 0.03, green: 0.035, blue: 0.15).opacity(0.36) }
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }

    private func color(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 255) / 255,
              green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}

/// A broad curved fold, rather than a cropped ellipse whose visible edge reads as a line.
/// Only its control points move; the glass controls stay still over the flowing wallpaper.
private struct SettingsPreviewFold: Shape {
    var phase: Double

    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        path.move(to: point(-0.24, 0.66 + phase * 0.12))
        path.addCurve(to: point(1.18, 0.07),
                      control1: point(0.43, 1.60 - phase * 0.25),
                      control2: point(0.46, -0.66 + phase * 0.30))
        path.addLine(to: point(1.18, 0.53))
        path.addCurve(to: point(-0.24, 1.08),
                      control1: point(0.52, -0.12 + phase * 0.22),
                      control2: point(0.60, 1.72 - phase * 0.18))
        path.closeSubpath()
        return path
    }
}

public extension View {
    /// A miniature window's surface, confined to settings illustrations.
    func settingsPreviewSurface(cornerRadius: CGFloat = 12) -> some View {
        modifier(SettingsPreviewSurface(cornerRadius: cornerRadius))
    }
}

private struct SettingsPreviewSurface: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.skin) private var skin
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var hovered = false

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous) }

    @ViewBuilder func body(content: Content) -> some View {
        switch skin {
        case .liquidGlass:
            surface(content)
                .overlay(shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.25), .white.opacity(0.62)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8))
                .overlay(shape.inset(by: 2).strokeBorder(.white.opacity(hovered ? 0.45 : 0.23), lineWidth: 0.7))
                .overlay(shape.fill(LinearGradient(colors: [.white.opacity(hovered ? 0.14 : 0), .clear],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing)).allowsHitTesting(false))
                .onHover { hovered = $0 }
                .animation(.easeOut(duration: 0.2), value: hovered)
                .shadow(color: Color(red: 0.08, green: 0.14, blue: 0.34).opacity(0.25), radius: 10, y: 6)
        case .classic:
            content.background(.background, in: shape)
                .overlay(shape.strokeBorder(.separator, lineWidth: 0.7))
                .shadow(color: .black.opacity(0.12), radius: 7, y: 4)
        }
    }

    @ViewBuilder private func surface(_ content: Content) -> some View {
        if reduceTransparency {
            content.background(.background, in: shape)
        } else {
            content
                .background(LinearGradient(colors: [.white.opacity(colorScheme == .dark ? 0.1 : 0.2),
                                                    .white.opacity(0.04)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing), in: shape)
                .glassEffect(.clear, in: shape)
        }
    }
}

/// The same glass controls and refracted wallpaper as the approved material study.
public struct SettingsAppearanceSample: View {
    private let skin: Skin
    @State private var hovering = false

    public init(skin: Skin) { self.skin = skin }

    public var body: some View {
        SettingsAppearanceScene(skin: skin, hovering: hovering)
            .onHover { hovering = $0 }
    }
}

/// Kept separate from pointer tracking so the native gallery can render hover transitions.
struct SettingsAppearanceScene: View {
    let skin: Skin
    let hovering: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            SettingsPreviewBackdrop()
                .scaleEffect(hovering && !reduceMotion ? 1.04 : 1)
            GeometryReader { room in
                miniature
                    .scaleEffect(min(1, max(0.1, (room.size.width - 32) / 144)))
                    .frame(width: room.size.width, height: room.size.height)
                    // Keep live glass sampling intact; a 3D transform makes it opaque.
                    .offset(y: hovering && !reduceMotion ? -3 : 0)
            }
        }
        .environment(\.skin, skin)
        .frame(height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: hovering)
        .accessibilityHidden(true)
    }

    private var miniature: some View {
        Group {
            if skin == .liquidGlass {
                glassControls
                    .padding(16).frame(width: 144, height: 99)
                    .settingsPreviewSurface(cornerRadius: 24)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(.white.opacity(hovering ? 0.4 : 0), lineWidth: 1)
                    }
            } else {
                SettingsWindowIllustration(title: L10n.text("overlaykit.document"), bundleID: "com.apple.TextEdit")
                    .frame(width: 144, height: 99)
                    .settingsPreviewSurface(cornerRadius: 9)
            }
        }
    }

    private var glassControls: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("Aa").font(.system(size: 25, weight: .medium, design: .rounded))
                Spacer()
                Capsule().fill(.blue.gradient).frame(width: 30, height: 18)
                    .overlay(alignment: .trailing) {
                        Circle().fill(.white).frame(width: 14, height: 14).padding(2)
                            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    }
            }
            Capsule().fill(.white.opacity(0.45)).frame(width: 62, height: 3)
            HStack(spacing: 9) {
                Image(systemName: "minus")
                GeometryReader { room in
                    Capsule().fill(.white.opacity(0.25))
                        .overlay(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.9)).frame(width: room.size.width * 0.64)
                        }
                }.frame(height: 5)
                Image(systemName: "plus")
            }.font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(.white)
        .shadow(color: .indigo.opacity(0.25), radius: 2, y: 1)
    }
}


/// The same miniature tab strip in the tab settings and saved workspace previews.
public struct SettingsTabIllustration: View {
    public struct Tab: Identifiable {
        public let id: String
        let title: String
        let bundleID: String?

        public init(id: String, title: String, bundleID: String?) {
            self.id = id
            self.title = title
            self.bundleID = bundleID
        }
    }

    private let tabs: [Tab]
    private let active: String
    private let height: CGFloat
    private let showsNames: Bool
    private let onSelect: ((String) -> Void)?
    @State private var hovered: String?
    @Environment(\.skin) private var skin

    public init(tabs: [Tab], active: String, height: CGFloat, showsNames: Bool = true,
                onSelect: ((String) -> Void)? = nil) {
        self.tabs = tabs
        self.active = active
        self.height = height
        self.showsNames = showsNames
        self.onSelect = onSelect
    }

    public var body: some View {
        HStack(spacing: 3) {
            ForEach(tabs) { tab in
                if let onSelect {
                    Button { onSelect(tab.id) } label: { label(for: tab) }
                        .buttonStyle(.plain)
                        .onHover { hovered = $0 ? tab.id : nil }
                        .accessibilityLabel(L10n.text("overlaykit.preview.tab", String(describing: (tab.title))))
                        .accessibilityAddTraits(tab.id == active ? .isSelected : [])
                        .help(L10n.text("overlaykit.select.and.focus.it.when.opening.the", String(describing: (tab.title))))
                } else {
                    label(for: tab)
                }
            }
        }
        .padding(min(4, height * 0.13)).frame(height: height)
        .settingsPreviewSurface(cornerRadius: height / 2)
    }

    private func label(for tab: Tab) -> some View {
        HStack(spacing: 5) {
            icon(tab.bundleID).resizable().scaledToFit()
                .frame(width: min(14, height * 0.48), height: min(14, height * 0.48))
            if showsNames {
                Text(tab.title).font(.system(size: min(10, height * 0.36), weight: tab.id == active ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, showsNames ? 7 : 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tabFill(for: tab), in: Capsule())
        .contentShape(Capsule())
    }

    private func tabFill(for tab: Tab) -> AnyShapeStyle {
        if skin == .liquidGlass {
            return AnyShapeStyle(.white.opacity(tab.id == active ? 0.55 : hovered == tab.id ? 0.18 : 0.04))
        }
        return AnyShapeStyle(.tint.opacity(tab.id == active ? 0.18 : hovered == tab.id ? 0.08 : 0))
    }

    private func icon(_ bundleID: String?) -> Image {
        if let image = AppIconProvider.shared.icon(pid: nil, bundleID: bundleID) { return Image(nsImage: image) }
        return Image(systemName: "macwindow")
    }
}

/// Every skin shares the tab strip, saved window identity and selection interactions.
public struct SettingsCheckpointTile: View {
    private let title: String
    private let bundleID: String?
    private let tabs: [SettingsTabIllustration.Tab]
    private let active: String
    private let showsNames: Bool
    private let focused: Bool
    private let onSelect: ((String) -> Void)?
    private let onFocus: (() -> Void)?

    public init(title: String, bundleID: String?, tabs: [SettingsTabIllustration.Tab], active: String,
                showsNames: Bool, focused: Bool, onSelect: ((String) -> Void)? = nil, onFocus: (() -> Void)? = nil) {
        self.title = title
        self.bundleID = bundleID
        self.tabs = tabs
        self.active = active
        self.showsNames = showsNames
        self.focused = focused
        self.onSelect = onSelect
        self.onFocus = onFocus
    }

    public var body: some View {
        GeometryReader { room in
            VStack(spacing: tabs.isEmpty ? 0 : 5) {
                if !tabs.isEmpty {
                    SettingsTabIllustration(tabs: tabs, active: active, height: min(26, room.size.height * 0.28),
                                            showsNames: showsNames, onSelect: onSelect)
                }
                if let onFocus {
                    Button(action: onFocus) { window.contentShape(RoundedRectangle(cornerRadius: 8)) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.text("overlaykit.bring.to.front.in.preview", String(describing: (title))))
                        .help(L10n.text("overlaykit.bring.to.front.in.the.preview.and"))
                } else { window }
            }
        }
    }

    private var window: some View {
        SettingsWindowIllustration(title: title, bundleID: bundleID, contentStyle: .appIdentity)
            .settingsPreviewSurface(cornerRadius: 8)
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(focused ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 2))
    }

}

public struct SettingsCheckpointBackground: View {
    @Environment(\.skin) private var skin
    public init() {}
    public var body: some View {
        if skin == .classic { RoundedRectangle(cornerRadius: 8).fill(.quaternary) }
        else { Color.clear }
    }
}

public extension View {
    /// A selectable library item, with an independent glass surface and an explicit selection rim.
    func settingsLibraryCard(selected: Bool) -> some View {
        modifier(SettingsLibraryCard(selected: selected))
    }
}

private struct SettingsLibraryCard: ViewModifier {
    let selected: Bool
    @Environment(\.skin) private var skin
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var hovered = false
    @Environment(\.colorSchemeContrast) private var contrast
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }

    func body(content: Content) -> some View {
        surface(content)
            .background(SettingsListSelection().allowsHitTesting(false))
            .overlay(shape.strokeBorder(selected ? Color.accentColor.opacity(0.65) : Color.primary.opacity(0.08),
                                        lineWidth: selected && contrast == .increased ? 2 : 0.8))
    }

    @ViewBuilder private func surface(_ content: Content) -> some View {
        if skin == .liquidGlass && !reduceTransparency {
            content
                .background(selected ? Color.accentColor.opacity(0.09) : .clear, in: shape)
                .glassEffect(.regular, in: shape)
                // The library uses outlines, including for selection; trim the glass's outer shadow.
                .clipShape(shape)
        } else {
            content.background(selected ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor), in: shape)
        }
    }
}


/// Keep List's keyboard selection, double-click action and reordering, but let the row draw
/// selection. This touches only the enclosing public NSTableView's paint, never its data source.
struct SettingsListSelection: NSViewRepresentable {
    func makeNSView(context: Context) -> SelectionView { SelectionView() }
    func updateNSView(_ view: SelectionView, context: Context) { view.suppressRowHighlight() }

    final class SelectionView: NSView {
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); suppressRowHighlight() }
        override func viewWillDraw() { suppressRowHighlight(); super.viewWillDraw() }

        func suppressRowHighlight() {
            guard let table = enclosingScrollView?.documentView as? NSTableView,
                  table.selectionHighlightStyle != .none else { return }
            table.selectionHighlightStyle = .none
        }
    }
}
