/// Whether each display has its own Spaces ("Displays have separate Spaces"). The window
/// server's Space list is authoritative for the running session, since the setting only
/// takes effect after logging in again; it names the shared set "Main". The preference is
/// the fallback. `NSScreen.screensHaveSeparateSpaces` is not used because it reports false
/// until `NSApplication` has started.
enum SeparateSpaces {
    static func isOn(displayIdentifiers: [String]?, spansDisplaysPreference: Bool?) -> Bool {
        if let displayIdentifiers { return !displayIdentifiers.contains("Main") }
        return spansDisplaysPreference != true
    }
}
