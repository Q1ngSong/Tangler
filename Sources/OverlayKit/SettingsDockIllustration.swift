import CoreKit
import SwiftUI

/// A hover-driven Dock on the same shared stage. One task replaces all pending hover requests.
struct SettingsDockIllustration: View {
    let enabled: Bool
    let showDelay: Double
    let hideDelay: Double
    let singleWindow: Bool
    let animates: Bool
    @State private var target: Int? = 0
    @State private var selected: Int? = 0
    @State private var focusedWindow: Int?
    @FocusState private var focusedIcon: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.settingsPreviewTime) private var fixedTime

    private var shown: Int? { enabled && (selected != 2 || singleWindow) ? selected : nil }
    private var motion: Animation? { reduceMotion || !animates ? nil : .smooth(duration: 0.22) }

    var body: some View {
        GeometryReader { room in
            let scale = min(room.size.width / 460, room.size.height / 272)
            VStack(spacing: 12) {
                ZStack(alignment: .bottom) {
                    if let shown {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 6) {
                                SettingsIllustrationApp.icon(shown).frame(width: 18, height: 18)
                                Text(SettingsIllustrationApp.name(shown)).font(.system(size: 11, weight: .medium))
                                Spacer()
                                Text(L10n.count("settings.preview.windows", shown == 2 ? 1 : 2))
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            HStack(spacing: 8) {
                                ForEach(0..<(shown == 2 ? 1 : 2), id: \.self) { variant in
                                    Button {
                                        withAnimation(motion) { focusedWindow = variant }
                                    } label: {
                                        SettingsWindowIllustration(title: SettingsIllustrationApp.title(shown, variant: variant),
                                            bundleID: SettingsIllustrationApp.bundles[shown], variant: variant)
                                            .frame(height: 82).settingsPreviewSurface(cornerRadius: 9)
                                            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(focusedWindow == variant ? 0.95 : 0), lineWidth: 2))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(SettingsIllustrationApp.title(shown, variant: variant))
                                    .accessibilityAddTraits(focusedWindow == variant ? .isSelected : [])
                                }
                            }
                        }
                        .padding(11).frame(width: shown == 2 ? 206 : 368)
                        .settingsPreviewSurface(cornerRadius: 19)
                        .id(shown).transition(.opacity)
                    } else {
                        Text(L10n.text(enabled ? "settings.preview.dock.hover" : "settings.preview.dock.disabled"))
                            .font(.system(size: 12)).foregroundStyle(.white).padding(16)
                    }
                }.frame(height: 132)
                HStack(alignment: .bottom, spacing: 15) {
                    ForEach([3, 0, 1, 2], id: \.self) { index in
                        Button { target = index } label: {
                            VStack(spacing: 3) {
                                SettingsIllustrationApp.icon(index).frame(width: 36, height: 36)
                                    .scaleEffect(target == index && !reduceMotion ? 1.09 : 1)
                                    .offset(y: target == index && !reduceMotion ? -4 : 0)
                                Circle().fill(.white.opacity(0.9)).frame(width: 4, height: 4)
                            }.frame(width: 40, height: 48)
                        }
                        .buttonStyle(.plain).focused($focusedIcon, equals: index)
                        .onHover { if $0 { target = index } }
                        .help(SettingsIllustrationApp.name(index))
                        .accessibilityLabel(SettingsIllustrationApp.name(index))
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .settingsPreviewSurface(cornerRadius: 20)
                SettingsPreviewInputHint(.gesture(symbol: "cursorarrow", label: L10n.text("settings.preview.dock.hover")))
            }
            .frame(width: 460, height: 272).scaleEffect(scale)
            .frame(width: room.size.width, height: room.size.height)
        }
        .contentShape(Rectangle())
        .onHover { if !$0 { target = nil } }
        .onChange(of: focusedIcon) { _, value in if let value { target = value } }
        .animation(motion, value: target)
        .task(id: target) {
            guard fixedTime == nil else { return }
            let requested = target
            do { try await Task.sleep(for: .seconds(max(0, requested == nil ? hideDelay : showDelay))) }
            catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(motion) { selected = requested; focusedWindow = nil }
        }
    }
}
