import Contracts
import CoreKit
import Foundation

/// One vocabulary for function buttons, configured input hints and miniature demonstrations.
/// These actions only change illustrative state; they never dispatch application commands.
public enum SettingsPreviewAction: String, CaseIterable, Identifiable {
    case leftHalf = "layout.leftHalf", rightHalf = "layout.rightHalf", maximize = "layout.maximize"
    case topHalf = "layout.topHalf", bottomHalf = "layout.bottomHalf"
    case topLeft = "layout.topLeft", topRight = "layout.topRight"
    case bottomLeft = "layout.bottomLeft", bottomRight = "layout.bottomRight"
    case center = "layout.center", restore = "layout.restore"
    case tabHeight, join = "tabs.addWindow", previousTab = "tabs.previous", nextTab = "tabs.next"
    case previousWindow = "switcher.allWindowsReverse", nextWindow = "switcher.allWindows"
    case openSearch = "palette.open", executeSearch

    public var id: String { rawValue }
    public init?(command: CommandID) { self.init(rawValue: command.rawValue) }

    var input: SettingsPreviewInput {
        switch self {
        case .tabHeight: .gesture(symbol: "slider.horizontal.3", label: title)
        case .executeSearch: .gesture(symbol: "return", label: L10n.text("settings.preview.search.execute"))
        default: .command(CommandID(rawValue: rawValue))
        }
    }

    var title: String {
        let key: String
        switch self {
        case .leftHalf: key = "overlaykit.left.half"
        case .rightHalf: key = "windowlayout.right.half"
        case .maximize: key = "windowlayout.maximize"
        case .topHalf: key = "windowlayout.top.half"
        case .bottomHalf: key = "windowlayout.bottom.half"
        case .topLeft: key = "windowlayout.top.left.quarter"
        case .topRight: key = "windowlayout.top.right.quarter"
        case .bottomLeft: key = "windowlayout.bottom.left.quarter"
        case .bottomRight: key = "windowlayout.bottom.right.quarter"
        case .center: key = "windowlayout.center"
        case .restore: key = "windowlayout.restore.previous.position"
        case .tabHeight: key = "settings.tabs.height"
        case .join: key = "settings.tabs.join"
        case .previousTab: key = "tabgroups.previous.tab"
        case .nextTab: key = "tabgroups.next.tab"
        case .previousWindow: key = "settings.preview.switch.left"
        case .nextWindow: key = "settings.preview.switch.right"
        case .openSearch: key = "settings.preview.search.open"
        case .executeSearch: key = "settings.preview.search.execute"
        }
        return L10n.text(key)
    }

    /// Unit coordinates keep the same placement at every preview size.
    var placement: CGRect? {
        switch self {
        case .leftHalf: CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .rightHalf: CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .topHalf: CGRect(x: 0, y: 0, width: 1, height: 0.5)
        case .bottomHalf: CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        case .topLeft: CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .topRight: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .bottomLeft: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .bottomRight: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .maximize: CGRect(x: 0, y: 0, width: 1, height: 1)
        case .center: CGRect(x: 0.2, y: 0.15, width: 0.6, height: 0.7)
        case .restore: CGRect(x: 0.36, y: 0.25, width: 0.55, height: 0.65)
        default: nil
        }
    }
}

/// Shared cyclic selection; each interaction replaces the current demonstration.
struct SettingsPreviewSelection {
    private(set) var revision = 0
    private(set) var previous = 0
    private(set) var selected = 0

    mutating func select(_ index: Int, count: Int) {
        guard count > 0 else { return }
        previous = selected
        selected = ((index % count) + count) % count
        revision += 1
    }

    mutating func step(_ delta: Int, count: Int) { select(selected + delta, count: count) }
}
