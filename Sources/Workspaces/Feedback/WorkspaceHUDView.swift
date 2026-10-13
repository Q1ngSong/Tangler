import CoreKit
import OverlayKit
import SwiftUI

/// A short message, or an expansion report with one line per entry, problems first.
struct WorkspaceHUDView: View {
    enum Content {
        case message(String)
        case expansion(ExpansionReport)
    }

    static let maximumLines = 8

    let content: Content

    /// A short message is a capsule, like Tahoe's volume HUD; a report is a panel.
    private var isMessage: Bool {
        switch content {
        case .message: true
        case .expansion: false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch content {
            case .message(let text):
                Text(text).font(.system(size: 13, weight: .medium))
            case .expansion(let report):
                Text(report.isFinished ? L10n.text("workspaces.workspace", String(describing: (report.workspaceName))) : L10n.text("workspaces.expanding.workspace", String(describing: (report.workspaceName))))
                    .font(.system(size: 13, weight: .semibold))
                Text(report.summary).font(.system(size: 12)).foregroundStyle(.secondary)
                let lines = Self.lines(of: report)
                ForEach(lines) { entry in
                    ExpansionEntryRow(entry: entry)
                }
                if report.entries.count > lines.count {
                    Text(L10n.count("workspaces.additional.windows.ready", report.entries.count - lines.count))
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(14)
        .fixedSize()
        .surface(.panel(isMessage ? .toast : .report))
    }

    /// Entries that need attention come first; the rest fill up to `maximumLines`.
    static func lines(of report: ExpansionReport) -> [ExpansionReport.Entry] {
        let problems = report.entries.filter { !$0.state.hasWindow || $0.note != nil }
        let fine = report.entries.filter { $0.state.hasWindow && $0.note == nil }
        return Array((problems + fine).prefix(maximumLines))
    }
}

/// One entry of a checkpoint and what expanding did for it.
struct ExpansionEntryRow: View {
    let entry: ExpansionReport.Entry

    var body: some View {
        ReportLine(label: entry.label, detail: entry.note.map { entry.state.text + L10n.text("text.reasonSeparator") + $0 } ?? entry.state.text,
                   symbol: symbol, tint: tint)
    }

    private var symbol: String {
        switch entry.state {
        case .alreadyHere, .moved, .opened, .launched:
            return entry.note == nil ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        case .waiting: return "clock"
        case .notRunning, .contentsNotOpened, .noNewWindow, .notMoved, .timedOut: return "xmark.circle.fill"
        case .cancelled: return "minus.circle"
        }
    }

    private var tint: Color {
        switch entry.state {
        case .alreadyHere, .moved, .opened, .launched: return entry.note == nil ? .green : .orange
        case .waiting, .cancelled: return .secondary
        case .notRunning, .contentsNotOpened, .noNewWindow, .notMoved, .timedOut: return .red
        }
    }
}

/// A symbol, a window's label and what happened to it.
private struct ReportLine: View {
    let label: String
    let detail: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(tint).font(.system(size: 11))
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(width: 320, alignment: .leading)
        }
    }
}
