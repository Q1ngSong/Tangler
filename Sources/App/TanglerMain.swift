import AppKit
import CoreKit
import SettingsKit

@main
enum TanglerMain {
    static let version = "0.0.1"
    @MainActor private static var delegate: AppDelegate?

    @MainActor
    static func main() {
        L10n.configure(UserDefaultsSettingsStore().load(AppSettings.self).language)
        let app = NSApplication.shared
        let delegate = AppDelegate()
        self.delegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
