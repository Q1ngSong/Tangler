import Contracts
import SwiftUI

/// The leader key's hint panel: one row per next key, key cap then name; rows that lead to
/// more keys end with a chevron. It sizes itself to its rows, so show it with
/// `OverlayHost.show(_:placement:)`, typically in an `OverlayStyle.hud` host.
public struct HintPanelView: View {
    private let rows: [HintRow]
    private let title: String?
    private let footer: String?
    private let dimmed: Bool

    /// `title` names the keys typed so far, e.g. "移到其他显示器"; `footer` can say how to leave.
    /// `dimmed` while the panel lingers after a command.
    public init(rows: [HintRow], title: String? = nil, footer: String? = nil, dimmed: Bool = false) {
        self.rows = rows
        self.title = title
        self.footer = footer
        self.dimmed = dimmed
    }

    public init(options: [LeaderOption], title: String? = nil, footer: String? = nil, dimmed: Bool = false) {
        self.init(rows: HintRow.rows(from: options), title: title, footer: footer, dimmed: dimmed)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                // Modifiers on a GridRow would turn it into one full-width cell, so the
                // accessibility label sits on the key cap and the other cells are hidden.
                ForEach(rows) { row in
                    GridRow {
                        KeyCap(row.key)
                            .gridColumnAlignment(.center)
                            .accessibilityLabel(row.accessibilityLabel)
                        Text(row.title).font(.system(size: 13)).lineLimit(1).accessibilityHidden(true)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .opacity(row.isGroup ? 1 : 0)
                            .accessibilityHidden(true)
                    }
                }
            }
            if let footer {
                Text(footer).font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .fixedSize()
        .surface(.panel(.hints(dimmed: dimmed)))
    }
}
