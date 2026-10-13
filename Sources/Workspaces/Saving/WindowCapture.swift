import Contracts
import CoreGraphics
import CoreKit
import Foundation

/// Turns the open windows into a workspace's saved windows (design section 4.5).
enum WindowCapture {
    struct Result: Equatable {
        var windows: [SavedWindow]
        /// The saved window that had the focus.
        var focused: UUID?
        var tabGroups: [SavedTabGroup] = []
        /// Width over height of the visible frame of the display the capture is drawn on.
        var screenAspect: Double?
        /// The windows were taken wherever they are: no desktop was asked for, or the service
        /// could not tell which desktop any window is on.
        var fromEveryDesktop = false
    }

    /// With a desktop, only that desktop's windows are captured.
    static func capture(from service: any WindowService, tabGroups: (any TabGroupService)?,
                        desktop: SpaceInfo? = nil) async -> Result {
        async let windows = service.windows()
        async let displays = service.displays()
        async let focused = service.focusedWindowID()
        let groups = await tabGroups?.groups() ?? []
        return await capture(windows: windows, displays: displays, groups: groups, focusedID: focused, desktop: desktop)
    }

    /// Every window except minimized and full-screen ones, which have no frame to restore,
    /// and Tangler's own. A tab group is recorded while two of its windows are captured.
    /// With a desktop, only the windows that are on it and on no other (workspaces design 6.2):
    /// a window shown on every desktop belongs to none. When no window says where it is, as
    /// without the private Space queries, all are captured rather than none.
    static func capture(windows: [WindowInfo], displays: [DisplayInfo], groups: [TabGroupSnapshot], focusedID: WindowID?,
                        desktop: SpaceInfo? = nil, ownPID: Int32 = ProcessInfo.processInfo.processIdentifier) -> Result {
        let only = windows.contains { !$0.spaceIDs.isEmpty } ? desktop?.id : nil
        var result = Result(windows: [], focused: nil, fromEveryDesktop: only == nil)
        var ids: [WindowID: UUID] = [:]
        var homes: [UUID: DisplayInfo] = [:]
        for window in windows where !window.isMinimized && !window.isFullscreen && window.pid != ownPID {
            if let only, window.spaceIDs != [only] { continue }
            guard window.frame.isFiniteRect, !window.frame.isEmpty,
                  let display = display(for: window, in: displays) else { continue }
            let item = SavedWindow(id: UUID(), bundleID: window.bundleID, appName: window.appName, title: window.title,
                                   displayID: display.id, unitFrame: UnitRect(frame: window.frame, in: display.visibleFrame),
                                   frame: window.frame,
                                   contents: ReopenTarget.detected(documentURL: window.documentURL).map { [$0] } ?? [],
                                   lastWindow: WindowRef(windowID: window.id, pid: window.pid))
            if window.id == focusedID { result.focused = item.id }
            ids[window.id] = item.id
            homes[item.id] = display
            result.windows.append(item)
        }
        for group in groups {
            let members = group.members.compactMap { ids[$0] }
            guard members.count >= 2, let first = members.first, let home = homes[ids[group.active] ?? first] else { continue }
            result.tabGroups.append(SavedTabGroup(members: members, active: ids[group.active] ?? first,
                                                  unitArea: UnitRect(frame: group.area, in: home.visibleFrame)))
        }
        // The board is the desktop's display, else that of the focused window, else the main one.
        let board = desktop.flatMap { desktop in displays.first { $0.id == desktop.displayID } }
            ?? result.focused.flatMap { homes[$0] } ?? displays.first(where: \.isMain) ?? displays.first
        if let frame = board?.visibleFrame, frame.width > 0, frame.height > 0 {
            result.screenAspect = Double(frame.width / frame.height)
        }
        return result
    }

    /// The window's own display, else the one it covers most, else the main display.
    private static func display(for window: WindowInfo, in displays: [DisplayInfo]) -> DisplayInfo? {
        if let known = displays.first(where: { $0.id == window.displayID }) { return known }
        let covered = displays.map { (display: $0, area: area(of: $0.frame.intersection(window.frame))) }
            .max { $0.area < $1.area }
        if let covered, covered.area > 0 { return covered.display }
        return displays.first(where: \.isMain) ?? displays.first
    }

    private static func area(of rect: CGRect) -> CGFloat {
        rect.isNull || rect.isEmpty ? 0 : rect.width * rect.height
    }
}
