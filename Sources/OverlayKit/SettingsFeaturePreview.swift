import CoreKit
import Contracts
import SwiftUI

/// Modules choose a scene; this template owns action selection, input cues and one-shot playback.
public struct SettingsFeaturePreview: View {
    public enum Scene: Equatable {
        case layout(gap: Double)
        case tabs(height: Double, joining: Bool)
        case switcher(height: Double)
        case dock(enabled: Bool, showDelay: Double = 0.35, hideDelay: Double = 0.2,
                  singleWindow: Bool = true, animates: Bool = true)
        case palette
        case command(CommandID)
    }

    private let title: String
    private let scene: Scene
    private let replay: Int
    @State private var action: SettingsPreviewAction
    @State private var selection = SettingsPreviewSelection()
    @State private var joined = false
    @State private var directSelection = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ title: String, scene: Scene, replay: Int = 0) {
        self.title = title
        self.scene = scene
        self.replay = replay
        _action = State(initialValue: Self.initialAction(scene))
        _joined = State(initialValue: Self.initialAction(scene) == .join)
    }

    public var body: some View {
        VStack(spacing: 10) {
            SettingsPreview(title, aspectRatio: 16.0 / 10, maxWidth: 560) {
                if case .dock(let enabled, let show, let hide, let single, let animates) = scene {
                    SettingsDockIllustration(enabled: enabled, showDelay: show, hideDelay: hide,
                                             singleWindow: single, animates: animates)
                } else {
                    SettingsPreviewPlayback(replay: selection.revision, repeats: false, autoplays: false, speed: 2.4) { phase in
                        VStack(spacing: 6) {
                            GeometryReader { room in
                                let scale = min(room.size.width / 460, room.size.height / 196)
                                illustration(phase)
                                    .frame(width: 460, height: 196, alignment: .topLeading)
                                    .scaleEffect(scale)
                                    .frame(width: room.size.width, height: room.size.height)
                            }
                            SettingsPreviewInputHint(directSelection ? .gesture(symbol: "cursorarrow", label: L10n.text("settings.preview.click")) : action.input,
                                playback: directSelection ? nil : .invocation(time: phase.time))
                                .padding(.horizontal, 8).padding(.bottom, 12)
                        }.padding(.top, 12)
                    }
                }
            }
            if !actions.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { actionButtons }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) { actionButtons }
                }
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            if isSwitcher {
                Text(L10n.text("settings.preview.switch.click"))
                    .font(SettingsTypography.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { if replay > 0 { choose(Self.initialAction(scene)) } }
        .onChange(of: replay) { _, _ in choose(Self.initialAction(scene)) }
        .onChange(of: scene) { old, new in
            if case .tabs(let previous, _) = old, case .tabs(let height, _) = new, previous != height {
                choose(.tabHeight)
            }
        }
    }

    private static func initialAction(_ scene: Scene) -> SettingsPreviewAction {
        switch scene {
        case .layout, .dock: .leftHalf
        case .tabs(_, let joining): joining ? .join : .tabHeight
        case .switcher: .nextWindow
        case .palette: .openSearch
        case .command(let id): SettingsPreviewAction(command: id) ?? .leftHalf
        }
    }

    private var actions: [SettingsPreviewAction] {
        switch scene {
        case .layout, .command: [.leftHalf, .rightHalf, .maximize]
        case .tabs: [.tabHeight, .join, .previousTab, .nextTab]
        case .switcher: [.previousWindow, .nextWindow]
        case .palette: [.openSearch, .executeSearch]
        case .dock: []
        }
    }

    private var isSwitcher: Bool { action == .previousWindow || action == .nextWindow }

    private var actionButtons: some View {
        ForEach(actions) { item in
            SettingsPreviewActionButton(item.title, selected: action == item && !directSelection) { choose(item) }
        }
    }

    private func choose(_ value: SettingsPreviewAction) {
        directSelection = false
        action = value
        switch value {
        case .previousTab: selection.step(-1, count: joined ? 3 : 2)
        case .nextTab: selection.step(1, count: joined ? 3 : 2)
        case .previousWindow: selection.step(-1, count: 3)
        case .nextWindow: selection.step(1, count: 3)
        case .join:
            joined = true
            selection.select(2, count: 3)
        default: selection.select(0, count: 3)
        }
    }

    @ViewBuilder private func illustration(_ phase: SettingsDemoPhase) -> some View {
        if action.placement != nil { layout(phase) }
        else if isSwitcher { switcher(phase) }
        else if action == .openSearch || action == .executeSearch { palette(phase) }
        else { tabs(phase) }
    }

    private func layout(_ phase: SettingsDemoPhase) -> some View {
        let gap: Double = if case .layout(let value) = scene { value * 0.2 } else { 3 }
        let target = action.placement ?? CGRect(x: 0, y: 0, width: 0.5, height: 1)
        let progress = phase.action
        return ZStack(alignment: .topLeading) {
            HStack(spacing: gap) {
                ForEach([SettingsPreviewAction.leftHalf, .rightHalf]) { item in
                    Button { choose(item) } label: {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white.opacity(action == item ? 0.16 : 0.05))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.55), lineWidth: 0.8))
                    }.buttonStyle(.plain).accessibilityLabel(item.title)
                }
            }.frame(width: 338, height: 166).offset(x: 61, y: 14)
            sampleWindow(0)
                .frame(width: mix(190, 338 * target.width - gap, progress), height: mix(124, 166 * target.height - gap, progress))
                .offset(x: mix(178, 61 + 338 * target.minX + gap / 2, progress), y: mix(44, 14 + 166 * target.minY + gap / 2, progress))
                .allowsHitTesting(false)
        }
    }

    private func tabs(_ phase: SettingsDemoPhase) -> some View {
        let configured: Double = if case .tabs(let height, _) = scene { height } else { 32 }
        let height = action == .tabHeight && selection.revision > 0 ? mix(max(20, configured - 10), configured, phase.action) : configured
        let adding = action == .join && !directSelection
        let hasThird = joined && (!adding || phase.action > 0.8)
        let index = directSelection || phase.action > 0.5 ? selection.selected : selection.previous
        let active = min(hasThird ? 2 : 1, index)
        return ZStack(alignment: .topLeading) {
            VStack(spacing: 5) {
                SettingsTabIllustration(tabs: Array(SettingsIllustrationApp.tabs.prefix(hasThird ? 3 : 2)),
                    active: String(active), height: min(48, height), onSelect: { id in
                        directSelection = true
                        selection.select(Int(id) ?? 0, count: hasThird ? 3 : 2)
                    })
                sampleWindow(active).frame(height: 122).id(active).transition(.opacity)
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: active)
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: hasThird)
            .frame(width: 300).offset(x: adding ? mix(46, 80, phase.action) : 80, y: 12)
            if adding {
                sampleWindow(2).frame(width: 138, height: 96)
                    .opacity(1 - phase.ramp(2.4, 2.8))
                    .offset(x: mix(276, 232, phase.action), y: mix(95, 17, phase.action))
                    .allowsHitTesting(false)
            }
        }
    }

    private func switcher(_ phase: SettingsDemoPhase) -> some View {
        let height: Double = if case .switcher(let value) = scene { min(118, 58 + value * 0.25) } else { 108 }
        let index = directSelection || phase.action > 0.4 ? selection.selected : selection.previous
        return HStack(spacing: 12) {
            ForEach(0..<3) { item in
                Button {
                    directSelection = true
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { selection.select(item, count: 3) }
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 5) {
                            SettingsIllustrationApp.icon(item).frame(width: 22, height: 22)
                            Text(SettingsIllustrationApp.name(item)).font(.system(size: 10, weight: .medium))
                        }
                        sampleWindow(item).frame(height: height)
                    }
                    .padding(9).settingsPreviewSurface(cornerRadius: 14)
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(index == item ? 0.95 : 0), lineWidth: 2))
                    .offset(y: index == item ? -4 : 0)
                }
                .buttonStyle(.plain).accessibilityLabel(SettingsIllustrationApp.name(item))
                .accessibilityAddTraits(index == item ? .isSelected : [])
            }
        }.frame(width: 406).offset(x: 27, y: 22)
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: index)
    }

    private func palette(_ phase: SettingsDemoPhase) -> some View {
        let executing = action == .executeSearch
        return ZStack(alignment: .topLeading) {
            sampleWindow(0).frame(width: executing ? mix(260, 162, phase.action) : 260, height: 154)
                .offset(x: executing ? mix(150, 68, phase.action) : 150, y: 20)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                    Text(executing ? L10n.text("overlaykit.left.half") : L10n.text("overlaykit.search.commands.windows.and.workspaces"))
                        .foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                }
                Divider()
                HStack { Label(L10n.text("overlaykit.left.half"), systemImage: "rectangle.lefthalf.filled"); Spacer(); Text("↵") }
                    .padding(8).foregroundStyle(.white)
                    .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 7))
                Label(L10n.text("overlaykit.open.workspace"), systemImage: "square.stack.3d.up")
                    .foregroundStyle(.secondary).padding(.horizontal, 8)
            }
            .font(.system(size: 12)).padding(14).frame(width: 324).settingsPreviewSurface(cornerRadius: 18)
            .opacity(executing ? 1 - phase.action : 0.35 + 0.65 * phase.action)
            .offset(x: 68, y: 24).allowsHitTesting(false)
        }
    }

    private func sampleWindow(_ index: Int) -> some View {
        SettingsWindowIllustration(title: SettingsIllustrationApp.title(index), bundleID: SettingsIllustrationApp.bundles[index])
            .settingsPreviewSurface(cornerRadius: 10)
    }

    private func mix(_ start: Double, _ end: Double, _ progress: Double) -> Double { start + (end - start) * progress }
}

/// Consistent hover feedback for every demonstration control, with no 3D window distortion.
struct SettingsPreviewActionButton: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ title: String, selected: Bool, action: @escaping () -> Void) {
        self.title = title; self.selected = selected; self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title).font(SettingsTypography.caption.weight(selected ? .semibold : .regular))
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
                .background(selected ? Color.accentColor.opacity(0.1) : Color.primary.opacity(hovered ? 0.07 : 0.035), in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? Color.accentColor.opacity(0.25) : .primary.opacity(0.08), lineWidth: 0.7))
                .offset(y: hovered && !reduceMotion ? -1 : 0)
        }
        .buttonStyle(.plain).onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: hovered)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Shared, synthetic app/window identities; all icons come from installed bundles when available.
enum SettingsIllustrationApp {
    static let bundles = ["com.apple.Safari", "com.microsoft.VSCode", "com.apple.Notes", "com.apple.finder"]
    static func name(_ index: Int) -> String {
        switch index {
        case 0: "Safari"
        case 1: "Code"
        case 2: L10n.text("overlaykit.notes")
        default: L10n.text("overlaykit.finder")
        }
    }
    static func title(_ index: Int, variant: Int = 0) -> String {
        switch index {
        case 0: L10n.text(variant == 0 ? "settings.preview.browser.references" : "settings.preview.browser.guide")
        case 1: variant == 0 ? "Tangler" : L10n.text("settings.preview.code.website")
        case 2: L10n.text("overlaykit.ideas.and.plans")
        default: L10n.text(variant == 0 ? "settings.preview.finder.documents" : "settings.preview.finder.downloads")
        }
    }
    static var tabs: [SettingsTabIllustration.Tab] {
        (0..<3).map { .init(id: String($0), title: name($0), bundleID: bundles[$0]) }
    }
    @MainActor static func icon(_ index: Int) -> some View {
        let image = AppIconProvider.shared.icon(pid: nil, bundleID: bundles[index]).map(Image.init(nsImage:))
            ?? Image(systemName: index == 1 ? "chevron.left.forwardslash.chevron.right" : "macwindow")
        return image.resizable().scaledToFit()
    }
}
