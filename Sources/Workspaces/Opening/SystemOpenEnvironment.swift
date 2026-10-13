import AppKit

extension OpenEnvironment {
    /// NSWorkspace, without activating the application, prompting or adding recent items.
    /// Requests carry only URLs: no arguments, Shell commands or AppleScript.
    static var system: OpenEnvironment {
        OpenEnvironment(
            applicationURL: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) },
            isRunning: { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty },
            pid: { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first?.processIdentifier },
            open: { request, applicationURL, completed in
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                configuration.addsToRecentItems = false
                configuration.promptsUserIfNeeded = false
                configuration.allowsRunningApplicationSubstitution = false
                let handler: @Sendable (NSRunningApplication?, (any Error)?) -> Void = { application, error in
                    let reply = OpenReply(bundleID: application?.bundleIdentifier, failed: error != nil || application == nil)
                    Task { @MainActor in completed(reply) }
                }
                if request.urls.isEmpty {
                    NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration,
                                                       completionHandler: handler)
                } else {
                    NSWorkspace.shared.open(request.urls, withApplicationAt: applicationURL,
                                            configuration: configuration, completionHandler: handler)
                }
            })
    }
}
