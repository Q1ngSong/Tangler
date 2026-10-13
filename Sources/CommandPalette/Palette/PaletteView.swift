import CoreKit
import OverlayKit
import SwiftUI

/// The search palette: a search field over one list of windows and commands. It fills the panel,
/// which `PaletteLayout` sizes to the rows.
struct PaletteView: View {
    let model: PaletteModel
    let actions: PaletteActions

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                SearchField(L10n.text("commandpalette.search.windows.and.commands.including.pinyin"), text: queryBinding, isFocused: focusBinding, fontSize: 20,
                            onEscape: actions.cancel, onSubmit: actions.submit,
                            onMoveUp: { actions.move(-1) }, onMoveDown: { actions.move(1) })
            }
            .padding(.horizontal, 16)
            .surface(.field(bandHeight: PaletteLayout.fieldHeight + PaletteLayout.dividerHeight))
            VStack(spacing: 0) {
                list
                if let message = model.message {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .frame(height: PaletteLayout.messageHeight)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .surface(.results)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .surface(.panel(.palette))
    }

    private var queryBinding: Binding<String> {
        Binding(get: { model.query }, set: { actions.setQuery($0) })
    }

    private var focusBinding: Binding<Bool> {
        Binding(get: { model.isFieldFocused }, set: { model.isFieldFocused = $0 })
    }

    @ViewBuilder
    private var list: some View {
        if model.results.isEmpty {
            Text(L10n.text("commandpalette.no.matching.windows.or.commands"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: PaletteLayout.rowHeight)
                .padding(.vertical, PaletteLayout.listPadding)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.results) { item in
                            PaletteRowView(item: item, isSelected: item.id == model.selectedID)
                                .frame(height: PaletteLayout.rowHeight)
                                .contentShape(Rectangle())
                                .onTapGesture { actions.choose(item.id) }
                                .id(item.id)
                        }
                    }
                    .padding(.vertical, PaletteLayout.listPadding)
                    .padding(.horizontal, 6)
                }
                .onChange(of: model.selectedID) { _, selected in
                    // No anchor: scrolls only as far as needed to show the row.
                    if let selected { proxy.scrollTo(selected) }
                }
            }
        }
    }
}
