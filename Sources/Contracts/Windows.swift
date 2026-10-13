import CoreGraphics
import Foundation

// All frames and points use global coordinates: origin at the top-left of the
// primary display, y grows downward (CoreGraphics and Accessibility convention).

public struct WindowInfo: Equatable, Sendable {
    public var id: WindowID
    public var pid: Int32
    public var bundleID: String?
    public var appName: String
    public var title: String
    public var frame: CGRect
    public var displayID: DisplayID?
    /// Empty when unknown, e.g. when the private Space queries are unavailable.
    public var spaceIDs: [SpaceID]
    public var isMinimized: Bool
    public var isFullscreen: Bool
    public var documentURL: URL?

    public init(id: WindowID, pid: Int32, bundleID: String? = nil, appName: String, title: String,
                frame: CGRect, displayID: DisplayID? = nil, spaceIDs: [SpaceID] = [],
                isMinimized: Bool = false, isFullscreen: Bool = false, documentURL: URL? = nil) {
        self.id = id
        self.pid = pid
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.frame = frame
        self.displayID = displayID
        self.spaceIDs = spaceIDs
        self.isMinimized = isMinimized
        self.isFullscreen = isFullscreen
        self.documentURL = documentURL
    }
}

public struct DisplayInfo: Equatable, Sendable {
    public var id: DisplayID
    public var name: String
    public var frame: CGRect
    /// The frame without the menu bar and the Dock.
    public var visibleFrame: CGRect
    public var isMain: Bool

    public init(id: DisplayID, name: String, frame: CGRect, visibleFrame: CGRect, isMain: Bool) {
        self.id = id
        self.name = name
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.isMain = isMain
    }
}

public struct SpaceInfo: Equatable, Sendable {
    public var id: SpaceID
    public var displayID: DisplayID
    /// 1-based among the display's ordinary desktops, matching Mission Control's "Desktop N";
    /// full-screen Spaces are numbered separately, so "第 N 个桌面" always means an ordinary one.
    public var index: Int
    public var isCurrent: Bool
    public var isFullscreen: Bool
    /// Names the desktop for as long as it exists; `id` is only good for this login session.
    /// Nil when the window server gives none, as for the first desktop on some systems; such a
    /// desktop cannot be told apart later.
    public var uuid: String?

    public init(id: SpaceID, displayID: DisplayID, index: Int, isCurrent: Bool, isFullscreen: Bool = false,
                uuid: String? = nil) {
        self.id = id
        self.displayID = displayID
        self.index = index
        self.isCurrent = isCurrent
        self.isFullscreen = isFullscreen
        self.uuid = uuid
    }
}

/// An application icon in the Dock.
public struct DockItem: Equatable, Sendable {
    public var appName: String
    public var bundleID: String?
    /// Nil when the application is not running.
    public var pid: Int32?
    public var iconFrame: CGRect
    public var dockEdge: ScreenEdge
    public var displayID: DisplayID?

    public init(appName: String, bundleID: String?, pid: Int32?, iconFrame: CGRect,
                dockEdge: ScreenEdge, displayID: DisplayID?) {
        self.appName = appName
        self.bundleID = bundleID
        self.pid = pid
        self.iconFrame = iconFrame
        self.dockEdge = dockEdge
        self.displayID = displayID
    }
}

/// Abilities that depend on private APIs; probed at launch (design section 5.2).
public struct WindowCapabilities: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let exactWindowIDs = WindowCapabilities(rawValue: 1 << 0)
    public static let otherSpaceWindows = WindowCapabilities(rawValue: 1 << 1)
    public static let spaceList = WindowCapabilities(rawValue: 1 << 2)
    public static let moveAcrossSpaces = WindowCapabilities(rawValue: 1 << 3)
    public static let preciseFocus = WindowCapabilities(rawValue: 1 << 4)
    /// Adding and removing desktops through Mission Control.
    public static let manageSpaces = WindowCapabilities(rawValue: 1 << 5)
    public static let all: WindowCapabilities = [.exactWindowIDs, .otherSpaceWindows, .spaceList,
                                                 .moveAcrossSpaces, .preciseFocus, .manageSpaces]
}

public enum WindowError: Error, Equatable, Sendable {
    case notAuthorized
    case windowNotFound(WindowID)
    case appNotResponding(pid: Int32)
    /// The window refused the request, e.g. a size below its minimum.
    case rejected(String)
    /// The ability is unavailable on this system; the string says why.
    case unsupported(String)
}

public enum FrameAnimation: Equatable, Sendable {
    case none
    case animated(seconds: Double)

    public static let standard: FrameAnimation = .animated(seconds: 0.18)
}

/// Window and application changes. Consumers switch over every case without `default`,
/// so adding a case makes the compiler point at each place that must handle it.
public enum WindowEvent: Equatable, Sendable {
    case appeared(WindowInfo)
    case disappeared(WindowID)
    case moved(WindowID, CGRect)
    case resized(WindowID, CGRect)
    case focused(WindowID)
    case minimized(WindowID)
    case restored(WindowID)
    case titleChanged(WindowID, String)
    case currentSpaceChanged
    /// The set of desktops changed: one was added or removed, moved in the order, or a full-screen
    /// Space came or went, through this service or by the user's hand. Read them with `spaces()`.
    /// Which desktop is current is not part of it: `.currentSpaceChanged` says that.
    case spacesChanged
    case displaysChanged
    /// Mission Control, App Exposé or Show Desktop came up, or the one that was up went away:
    /// what `WindowService.isExposeShowing` says changed.
    case exposeChanged(isShowing: Bool)
    case appLaunched(pid: Int32)
    case appTerminated(pid: Int32)
    case appHidden(pid: Int32)
    case appUnhidden(pid: Int32)
}
