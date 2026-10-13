import CoreKit
import CommandPalette
import Contracts
import OverlayKit
import SwiftUI

struct ShortcutsPage: View {
    let model: SettingsModel
    @Environment(\.settingsCompactLayout) private var compact
    @State private var query = ""
    @State private var module: ModuleID?
    @State private var trigger: LeaderTrigger = .holdRightCommand

    private var filters: [(id: ModuleID, title: String)] {
        FeatureCatalog.all.filter { !$0.declaredCommands.isEmpty }.map {
            ($0.moduleID, $0.moduleID == "palette" ? L10n.text("app.search") : $0.displayName)
        }
    }

    private var groups: [(module: String, specs: [CommandSpec])] {
        model.declaredCommands.compactMap { group in
            let specs = group.specs.filter { spec in
                guard module == nil || spec.module == module else { return false }
                var displayed = spec
                displayed.leaderKeys = model.leaderKeys(for: spec)
                return ShortcutSearch.matches(displayed, module: group.module, shortcut: model.shortcut(for: spec), query: query)
            }
            return specs.isEmpty ? nil : (group.module, specs)
        }
    }

    private var previewWidth: CGFloat { compact ? 126 : 174 }
    private let resetWidth: CGFloat = 24
    private var commandWidth: CGFloat { previewWidth + ShortcutRecorder.columnSpacing + ShortcutRecorder.actionWidth + resetWidth }

    var body: some View {
        SettingsPageTemplate {
            VStack(spacing: 16) {
                LeaderTriggerSettingsSection(store: model.composition.settings, input: model.composition.input,
                                             commands: model.composition.commands.commands,
                                             onTriggerChange: { trigger = $0 })
                searchField
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        filter(L10n.text("app.all"), id: nil)
                        ForEach(filters, id: \.id) { filter($0.title, id: $0.id) }
                    }
                }
                .scrollIndicators(.hidden).fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .contain).accessibilityLabel(L10n.text("app.filter.shortcuts.by.module"))
                commandTable
                HStack {
                    Text(L10n.count("app.features", groups.reduce(0) { $0 + $1.specs.count }))
                    Spacer(minLength: 4)
                    Text(L10n.text("app.record.then.save.esc.to.revert"))
                }.font(SettingsTypography.caption).foregroundStyle(.secondary)
            }
            .padding(compact ? 16 : SettingsPageLayout.contentInset)
        }
        .onAppear { model.refresh() }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(L10n.text("app.search.commands.modules.or.keys"), text: $query).textFieldStyle(.plain)
                .accessibilityLabel(L10n.text("app.search.commands.modules.or.keys"))
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help(L10n.text("app.clear.search"))
            }
        }
        .padding(.horizontal, 12).frame(height: 39)
        .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.1), lineWidth: 0.5))
    }

    private var commandTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(L10n.text("app.function")).frame(maxWidth: .infinity, alignment: .leading)
                Text(L10n.text("app.command")).frame(width: commandWidth)
            }
            .font(SettingsTypography.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 12).frame(height: 35)
            .background(.primary.opacity(0.015))
            Divider()
            if groups.isEmpty {
                ContentUnavailableView.search(text: query).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(groups, id: \.module) { group in
                            ForEach(group.specs, id: \.id) { spec in
                                commandRow(spec, module: group.module)
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
        .settingsGroupSurface()
        .accessibilityElement(children: .contain).accessibilityLabel(L10n.text("app.shortcut.commands"))
    }

    private func filter(_ title: String, id: ModuleID?) -> some View {
        Button { module = id } label: {
            Text(title).font(SettingsTypography.caption.weight(module == id ? .semibold : .regular))
                .padding(.horizontal, compact ? 9 : 12).padding(.vertical, 6)
                .foregroundStyle(module == id ? Color.accentColor : Color.secondary)
                .background(module == id ? Color.accentColor.opacity(0.1) : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(module == id ? Color.accentColor.opacity(0.18) : .clear, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(module == id ? .isSelected : [])
    }

    private func commandRow(_ spec: CommandSpec, module: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(spec.title).font(SettingsTypography.body.weight(.medium))
                    Text(module).font(SettingsTypography.caption).foregroundStyle(.secondary)
                }
                .padding(.trailing, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                ShortcutRecorder(chord: Binding(get: { model.shortcut(for: spec) },
                                                 set: { model.setShortcut($0, for: spec) }),
                                 showsKeySymbols: true, style: .confirmed(previewWidth: previewWidth),
                                 fallbackLabel: ShortcutKeySymbols.label(model.leaderKeys(for: spec), trigger: trigger),
                                 validate: { model.shortcutProblem($0, for: spec, trigger: trigger) },
                                 onRecordingChange: model.setRecording)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(L10n.text("app.shortcut.for", String(describing: (spec.title))))
                resetButton(spec).frame(width: resetWidth)
            }
            ForEach(model.overrideProblems.filter { $0.command == spec.id }, id: \.self) { problem in
                Label(problem.reason, systemImage: "exclamationmark.triangle")
                    .font(SettingsTypography.caption).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 12)
        .frame(minHeight: 64)
    }

    @ViewBuilder private func resetButton(_ spec: CommandSpec) -> some View {
        if model.isOverridden(spec) {
            Button { model.resetShortcut(for: spec) } label: { Image(systemName: "arrow.counterclockwise") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help(L10n.text("app.restore.default.shortcut")).accessibilityLabel(L10n.text("app.restore.the.default.shortcut.for", String(describing: (spec.title))))
        } else {
            Color.clear.frame(height: 1).accessibilityHidden(true)
        }
    }
}

enum ShortcutSearch {
    static func matches(_ spec: CommandSpec, module: String, shortcut: KeyChord?, query: String) -> Bool {
        let terms = query.split(whereSeparator: \.isWhitespace)
        let text = ([spec.title, module, shortcut?.description ?? "", shortcut.map(ShortcutKeySymbols.label) ?? ""] + spec.searchAliases + spec.leaderKeys.map(\.description))
            .joined(separator: " ")
        return terms.allSatisfy { text.localizedStandardContains($0) }
    }
}
