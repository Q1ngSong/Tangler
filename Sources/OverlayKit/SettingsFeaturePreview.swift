import CoreKit
import SwiftUI

/// A shared stage and playback clock; modules provide values and semantic input bindings.
public struct SettingsFeaturePreview: View {
    public enum Scene: Equatable {
        case layout(columns: Int, rows: Int, gap: Double)
        case tabs(height: Double, joining: Bool)
        case switcher(height: Double)
        case dock(enabled: Bool)
        case palette
    }

    private let title: String
    private let scene: Scene
    private let input: SettingsPreviewInput
    @Environment(\.settingsInputBindings) private var bindings

    public init(_ title: String, scene: Scene, input: SettingsPreviewInput) {
        self.title = title
        self.scene = scene
        self.input = input
    }

    public var body: some View {
        SettingsPreview(title, aspectRatio: 16.0 / 9, maxWidth: 480) {
            SettingsPreviewPlayback { phase in
                VStack(spacing: 0) {
                    GeometryReader { room in
                        let scale = min(room.size.width / 460, room.size.height / 196)
                        ZStack(alignment: .topLeading) {
                            illustration(phase)
                            cursor(phase)
                        }
                        .frame(width: 460, height: 196, alignment: .topLeading)
                        .scaleEffect(scale)
                        .frame(width: room.size.width, height: room.size.height)
                    }
                    .accessibilityHidden(true)
                    HStack {
                        Spacer(minLength: 0)
                        SettingsPreviewInputHint(previewInput(phase), active: inputActive(phase), playback: inputPlayback(phase))
                    }.padding(.horizontal, 12).padding(.bottom, 10)
                }.padding(.top, 8)
            }.id(title)
        }
    }

    @ViewBuilder private func illustration(_ phase: SettingsDemoPhase) -> some View {
        switch scene {
        case .layout(let columns, let rows, let gap): grid(columns: columns, rows: rows, gap: gap, phase: phase)
        case .tabs(let height, let joining): tabs(height: height, joining: joining, phase: phase)
        case .switcher(let height): switcher(height: height, phase: phase)
        case .dock(let enabled): dock(enabled: enabled, phase: phase)
        case .palette: palette(phase)
        }
    }

    private func grid(columns: Int, rows: Int, gap: Double, phase: SettingsDemoPhase) -> some View {
        let space = CGFloat(gap) * 0.18 + 2
        let width = max(1, (320 - space * CGFloat(columns - 1)) / CGFloat(columns))
        let height = max(1, (156 - space * CGFloat(rows - 1)) / CGFloat(rows))
        return ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                ForEach(0..<(columns * rows), id: \.self) { index in
                    RoundedRectangle(cornerRadius: min(7, height / 4))
                        .fill(.white.opacity(index == 0 ? 0.12 + phase.action * 0.2 : 0.04))
                        .overlay(RoundedRectangle(cornerRadius: min(7, height / 4))
                            .strokeBorder(.white.opacity(index == 0 ? 0.9 : 0.3), lineWidth: 0.8))
                        .frame(width: width, height: height)
                        .offset(x: CGFloat(index % columns) * (width + space), y: CGFloat(index / columns) * (height + space))
                }
            }
            .frame(width: 320, height: 156, alignment: .topLeading).padding(8).settingsPreviewSurface(cornerRadius: 16)
            .offset(x: 62, y: 10)
            sampleWindow("Apple", bundleID: "com.apple.Safari")
                .frame(width: mix(144, width, phase.action), height: mix(96, height, phase.action))
                .offset(x: mix(246, 70, phase.action), y: mix(66, 18, phase.action))
        }
    }

    private func tabs(height: Double, joining: Bool, phase: SettingsDemoPhase) -> some View {
        let progress = phase.action
        let barHeight = joining ? height : mix(max(20, height - 10), height, progress)
        let added = joining && progress > 0.9
        return ZStack(alignment: .topLeading) {
            VStack(spacing: 5) {
                SettingsTabIllustration(tabs: [
                    .init(id: "safari", title: "Apple", bundleID: "com.apple.Safari"),
                    .init(id: "notes", title: L10n.text("overlaykit.notes"), bundleID: "com.apple.Notes")
                ] + (added ? [.init(id: "document", title: L10n.text("overlaykit.document"), bundleID: "com.apple.TextEdit")] : []),
                    active: added ? "document" : "safari", height: barHeight)
                sampleWindow(added ? L10n.text("overlaykit.design.draft") : "Apple", bundleID: added ? "com.apple.TextEdit" : "com.apple.Safari")
                    .frame(height: 92)
            }
            .frame(width: 300).offset(x: joining ? mix(48, 80, progress) : 80, y: 15)
            if joining {
                sampleWindow(L10n.text("overlaykit.design.draft"), bundleID: "com.apple.TextEdit")
                    .frame(width: 136, height: 92)
                    .opacity(1 - phase.ramp(2.45, 2.85) * (1 - phase.ramp(6.3, 7.5)))
                    .offset(x: mix(270, 232, progress), y: mix(83, 21, progress))
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "textformat.size.smaller")
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.28))
                        Capsule().fill(.white.opacity(0.8)).frame(width: mix(48, 108, progress))
                        Circle().fill(.white).frame(width: 12, height: 12).offset(x: mix(42, 102, progress))
                    }.frame(width: 140, height: 4)
                    Image(systemName: "textformat.size.larger")
                }.font(.system(size: 12)).foregroundStyle(.white)
                    .frame(width: 210).offset(x: 125, y: 175)
            }
        }
    }

    private func switcher(height: Double, phase: SettingsDemoPhase) -> some View {
        let cardHeight = min(116, 50 + height * 0.26)
        let titles = ["Apple", L10n.text("overlaykit.notes"), L10n.text("overlaykit.document")]
        let names = ["Safari", L10n.text("overlaykit.notes"), L10n.text("overlaykit.finder")]
        let bundles = ["com.apple.Safari", "com.apple.Notes", "com.apple.finder"]
        let target = bindings.cyclesBackward(for: input) ? 2 : 1
        let selection = phase.ramp(2.05, 2.4)
        let committed = phase.ramp(3.45, 4.05)
        let reset = 1 - phase.ramp(6.3, 7.5)
        let panel = phase.ramp(0.95, 1.4) * (1 - committed)
        return ZStack(alignment: .topLeading) {
            sampleWindow("Apple", bundleID: "com.apple.Safari")
                .frame(width: 280, height: 134).offset(x: 64, y: 30)
                .opacity(1 - panel * 0.72)
            HStack(spacing: 10) {
                ForEach(0..<3) { index in
                    let selected = index == target ? selection : (index == 0 ? 1 - selection : 0)
                    VStack(spacing: 6) {
                        sampleWindow(titles[index], bundleID: bundles[index])
                            .frame(height: cardHeight)
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor.opacity(selected), lineWidth: 2))
                        Text(names[index]).font(.system(size: 10, weight: .medium))
                    }.offset(y: -selected * 4)
                }
            }
            .frame(width: 370).padding(12).settingsPreviewSurface(cornerRadius: 22)
            .scaleEffect(0.96 + panel * 0.04).opacity(panel)
            .offset(x: 33, y: 29)
            sampleWindow(titles[target], bundleID: bundles[target])
                .frame(width: mix(116, 292, committed), height: mix(cardHeight, 138, committed))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.8), lineWidth: 0.8))
                .offset(x: mix(45 + Double(target) * 126, 102, committed), y: mix(37, 47, committed))
                .opacity(committed * reset)
        }
    }

    private func dock(enabled: Bool, phase: SettingsDemoPhase) -> some View {
        let reset = 1 - phase.ramp(6.3, 7.5)
        let opened = phase.ramp(1.5, 2.05) * reset
        let chosen = phase.ramp(3.2, 3.85)
        return ZStack(alignment: .topLeading) {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    sampleWindow(L10n.text("overlaykit.start.page"), bundleID: "com.apple.Safari")
                    sampleWindow(L10n.text("overlaykit.design.document"), bundleID: "com.apple.Safari")
                }
                .frame(width: 276, height: 80).padding(9).settingsPreviewSurface(cornerRadius: 18)
                .scaleEffect(0.92 + opened * 0.08, anchor: .bottom)
                .opacity(enabled ? opened * (1 - chosen) : 0)
                .offset(y: 12 * (1 - opened))
                HStack(spacing: 18) {
                    appIcon("com.apple.finder")
                    appIcon("com.apple.Safari").scaleEffect(1 + opened * 0.18).offset(y: -opened * 3)
                    appIcon("com.apple.Notes")
                }
                .padding(.horizontal, 18).padding(.vertical, 8).settingsPreviewSurface(cornerRadius: 15)
            }.frame(width: 294).offset(x: 83, y: 17)
            sampleWindow(L10n.text("overlaykit.design.document"), bundleID: "com.apple.Safari")
                .frame(width: mix(134, 308, chosen), height: mix(80, 118, chosen))
                .offset(x: mix(234, 76, chosen), y: mix(26, 8, chosen))
                .opacity(enabled ? chosen * reset : 0)
        }
    }

    private func palette(_ phase: SettingsDemoPhase) -> some View {
        let opened = phase.ramp(2.1, 2.75) * (1 - phase.ramp(6.3, 7.5))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                Text(L10n.text("overlaykit.search.commands.windows.and.workspaces"))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Divider()
            HStack { Label(L10n.text("overlaykit.left.half"), systemImage: "rectangle.lefthalf.filled"); Spacer(); Text("↵") }
                .padding(.horizontal, 8).padding(.vertical, 7)
                .foregroundStyle(.white).background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 7))
            Label(L10n.text("overlaykit.open.workspace"), systemImage: "square.stack.3d.up").foregroundStyle(.secondary).padding(.horizontal, 8)
        }
        .font(.system(size: 12)).padding(14).frame(width: 324).settingsPreviewSurface(cornerRadius: 18)
        .scaleEffect(0.94 + opened * 0.06)
        .opacity(opened)
        .offset(x: 68, y: 25 + 14 * (1 - opened))
    }

    private func previewInput(_ phase: SettingsDemoPhase) -> SettingsPreviewInput {
        if case .dock(true) = scene, phase.time >= 2.35, phase.time < 4.5 {
            return .gesture(symbol: "cursorarrow.rays", label: L10n.text("overlaykit.click.a.window.preview"))
        }
        return input
    }

    private func inputActive(_ phase: SettingsDemoPhase) -> Bool {
        if case .dock = scene { return (1.5..<2.05).contains(phase.time) || (3.2..<3.65).contains(phase.time) }
        return phase.inputActive
    }

    private func inputPlayback(_ phase: SettingsDemoPhase) -> SettingsPreviewInputPlayback? {
        switch scene {
        case .switcher: .cycling(time: phase.time)
        case .palette: .invocation(time: phase.time)
        default: nil
        }
    }

    @ViewBuilder private func cursor(_ phase: SettingsDemoPhase) -> some View {
        switch scene {
        case .switcher, .palette: EmptyView()
        case .dock(let enabled): dockPointer(enabled: enabled, phase: phase)
        default: pointer(phase)
        }
    }

    private func dockPointer(enabled: Bool, phase: SettingsDemoPhase) -> some View {
        let approach = phase.ramp(0.6, 1.5)
        let toPreview = enabled ? phase.ramp(2.35, 3.1) : 0
        let click = enabled && (3.2...3.75).contains(phase.time) ? (phase.time - 3.2) / 0.55 : -1
        return SettingsPreviewCursor(click: click)
            .opacity(phase.ramp(0.2, 0.6) * (1 - phase.ramp(4, 4.5)))
            .offset(x: mix(mix(345, 230, approach), 294, toPreview),
                    y: mix(mix(177, 145, approach), 65, toPreview))
    }

    private func pointer(_ phase: SettingsDemoPhase) -> some View {
        let start: CGPoint
        let end: CGPoint
        switch scene {
        case .layout: start = CGPoint(x: 350, y: 91); end = CGPoint(x: 93, y: 37)
        case .tabs(_, true): start = CGPoint(x: 412, y: 163); end = CGPoint(x: 318, y: 99)
        case .tabs(_, false): start = CGPoint(x: 189, y: 182); end = CGPoint(x: 261, y: 182)
        case .switcher: start = CGPoint(x: 380, y: 167); end = CGPoint(x: 241, y: 99)
        case .dock: start = CGPoint(x: 345, y: 177); end = CGPoint(x: 230, y: 145)
        case .palette: start = CGPoint(x: 369, y: 171); end = CGPoint(x: 233, y: 61)
        }
        let progress: Double
        switch scene {
        case .layout, .tabs(_, false): progress = phase.action
        default: progress = phase.travel
        }
        return SettingsPreviewCursor(click: phase.click)
            .opacity(phase.cursorOpacity)
            .offset(x: mix(start.x, end.x, progress), y: mix(start.y, end.y, progress))
    }

    private func mix(_ start: Double, _ end: Double, _ progress: Double) -> Double { start + (end - start) * progress }

    private func sampleWindow(_ title: String, bundleID: String) -> some View {
        SettingsWindowIllustration(title: title, bundleID: bundleID).settingsPreviewSurface(cornerRadius: 10)
    }

    private func appIcon(_ bundleID: String) -> some View {
        let image = AppIconProvider.shared.icon(pid: nil, bundleID: bundleID).map(Image.init(nsImage:)) ?? Image(systemName: "macwindow")
        return image.resizable().scaledToFit().frame(width: 28, height: 28)
    }
}
