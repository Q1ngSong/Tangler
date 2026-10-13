import CoreKit
import Contracts

/// Which workspace is on which desktop (workspaces design, sections 4 and 6). Nothing here is
/// stored: it is worked out from the Space list each time, by the desktops' UUIDs and never by
/// their order, which the system changes.
enum WorkspaceDesktops {
    enum State: Equatable {
        case open(SpaceInfo)
        case closed

        var label: String {
            switch self {
            case .open(let desktop): return L10n.text("workspaces.open.desktop", String(describing: (desktop.index)))
            case .closed: return L10n.text("workspaces.closed")
            }
        }
    }

    /// What a workspace stores to own `space`; nil for a full-screen Space and for a desktop the
    /// system gives no UUID, which could not be found again.
    static func binding(for space: SpaceInfo) -> BoundDesktop? {
        guard !space.isFullscreen, let uuid = space.uuid, !uuid.isEmpty else { return nil }
        return BoundDesktop(uuid: uuid, displayID: space.displayID)
    }

    /// The workspace `space` belongs to. Stored data that binds one desktop twice gives it to the
    /// first workspace in the list.
    static func owner(of space: SpaceInfo, among workspaces: [Workspace]) -> Workspace? {
        guard let uuid = binding(for: space)?.uuid else { return nil }
        return workspaces.first { $0.desktop?.uuid == uuid }
    }

    /// Open while the workspace's desktop is listed and the workspace is the one that owns it.
    static func state(of workspace: Workspace, among workspaces: [Workspace], in spaces: [SpaceInfo]) -> State {
        guard let uuid = workspace.desktop?.uuid, !uuid.isEmpty,
              let desktop = spaces.first(where: { !$0.isFullscreen && $0.uuid == uuid }),
              owner(of: desktop, among: workspaces)?.id == workspace.id else { return .closed }
        return .open(desktop)
    }

    /// The Space showing on the display of the focused window, else on the main display.
    static func current(displays: [DisplayInfo], spaces: [SpaceInfo], focusedDisplay: DisplayID?) -> SpaceInfo? {
        func showing(on display: DisplayID?) -> SpaceInfo? {
            display.flatMap { id in spaces.first { $0.isCurrent && $0.displayID == id } }
        }
        return showing(on: focusedDisplay) ?? showing(on: (displays.first(where: \.isMain) ?? displays.first)?.id)
    }
}
