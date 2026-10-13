import AppKit
import Contracts

/// Identifies a cached application icon. Every process of an app shares its bundle ID,
/// which also survives relaunches, so it wins over the process ID. Launch Services
/// treats bundle IDs case-insensitively, and so does the key.
public enum AppIconKey: Hashable, Sendable {
    case bundleID(String)
    case pid(Int32)

    public init?(pid: Int32?, bundleID: String?) {
        if let bundleID, !bundleID.isEmpty {
            self = .bundleID(bundleID.lowercased())
        } else if let pid, pid > 0 {
            self = .pid(pid)
        } else {
            return nil
        }
    }
}

/// Application icons by process ID or bundle ID, cached for the lifetime of the provider.
@MainActor
public final class AppIconProvider {
    public typealias Loader = @MainActor (_ pid: Int32?, _ bundleID: String?) -> NSImage?

    public static let shared = AppIconProvider()

    private let loader: Loader
    private var cache: [AppIconKey: NSImage] = [:]

    public init(loader: @escaping Loader = AppIconProvider.systemIcon) {
        self.loader = loader
    }

    /// The icon, or nil when the app cannot be found. Misses are not cached, so an app that
    /// is still launching gets its icon on a later call. Treat the image as read-only: it is shared.
    public func icon(pid: Int32?, bundleID: String?) -> NSImage? {
        guard let key = AppIconKey(pid: pid, bundleID: bundleID) else { return nil }
        if let cached = cache[key] { return cached }
        guard let icon = loader(pid, bundleID) else { return nil }
        cache[key] = icon
        return icon
    }

    public func icon(for window: WindowInfo) -> NSImage? {
        icon(pid: window.pid, bundleID: window.bundleID)
    }

    public func icon(for item: DockItem) -> NSImage? {
        icon(pid: item.pid, bundleID: item.bundleID)
    }

    /// Drops an icon cached by process ID, e.g. after `.appTerminated`, because the system reuses process IDs.
    public func forget(pid: Int32) {
        cache[.pid(pid)] = nil
    }

    /// The running process's icon first, then the installed app's.
    public static func systemIcon(pid: Int32?, bundleID: String?) -> NSImage? {
        if let pid, pid > 0, let icon = NSRunningApplication(processIdentifier: pid)?.icon {
            return icon
        }
        guard let bundleID, !bundleID.isEmpty else { return nil }
        if let icon = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.icon {
            return icon
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
