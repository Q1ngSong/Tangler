import Foundation

/// Asks the Dock to open or close Mission Control, as the Mission Control key does.
enum DockNotification {
    /// The function's second argument is pointer-sized, and it returns a status.
    private typealias Send = @convention(c) (CFString, Int) -> Int32

    /// Thread safety of the call is not documented, so it runs on the main thread. The status is
    /// dropped: whether Mission Control opened or closed is read from the Dock.
    @MainActor
    static func toggleMissionControl() {
        _ = PrivateSymbols.function(.dockNotification, as: Send.self)?("com.apple.expose.awake" as CFString, 0)
    }
}
