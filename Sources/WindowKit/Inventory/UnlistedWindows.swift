import Contracts

/// Whether a window Accessibility no longer lists is still open. Windows on other Spaces and
/// windows of hidden apps drop out of its list, but so do windows an app closed while keeping
/// them for later (Slack, Discord and Spotify only order a window out on ⌘W), and the window
/// server goes on listing those. Only a Space showing the window, or its app being hidden,
/// tells them apart. Scans, destroyed elements and failed rereads all decide with this rule.
enum UnlistedWindows {
    /// nil when Spaces cannot be read: then only Accessibility's list counts, as in the legacy app.
    static func isOpen(appIsHidden: Bool, spaceIDs: [SpaceID]?) -> Bool? {
        guard let spaceIDs else { return nil }
        return appIsHidden || !spaceIDs.isEmpty
    }
}
