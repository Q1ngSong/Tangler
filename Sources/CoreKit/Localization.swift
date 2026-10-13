import Foundation
import Observation

/// Stored values are independent of the names shown in the language picker.
public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    public func resolved(preferredLanguages: [String]) -> AppLanguage {
        guard self == .system else { return self }
        let supported = ["en", "zh-Hans"]
        let match = Bundle.preferredLocalizations(from: supported, forPreferences: preferredLanguages).first
        return match == "zh-Hans" ? .simplifiedChinese : .english
    }

    public var title: String {
        switch self {
        case .system: L10n.text("settings.language.system")
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        }
    }
}

/// Native bundle lookup, with an explicit language for exports and isolated tests.
public struct Localizer: Sendable {
    public let language: AppLanguage
    public var locale: Locale { Locale(identifier: language.rawValue) }
    private let bundle: Bundle

    public init(language: AppLanguage, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.language = language.resolved(preferredLanguages: preferredLanguages)
        bundle = Self.languageBundle(self.language) ?? Self.english
    }

    /// Packaged apps require embedded resources; source builds and tests retain SwiftPM lookup.
    public static var resources: Bundle {
        if let url = Bundle.main.url(forResource: "Tangler_CoreKit", withExtension: "bundle"),
           let bundle = Bundle(url: url) { return bundle }
        #if TANGLER_APP_BUNDLE
        // SwiftPM's generated fallback embeds the developer's absolute build directory.
        fatalError("Missing embedded Tangler language resources")
        #else
        return Bundle.module
        #endif
    }

    public func text(_ key: String) -> String {
        let fallback = Self.english.localizedString(forKey: key, value: key, table: nil)
        return bundle.localizedString(forKey: key, value: fallback, table: nil)
    }

    public func format(_ key: String, _ arguments: [String]) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
    }

    /// Counts use native plural rules rather than concatenating translated fragments.
    public func count(_ key: String, _ count: Int) -> String {
        String(format: text(key), locale: locale, arguments: [count])
    }

    /// SwiftPM normalizes localization directory names to lowercase.
    private static func languageBundle(_ language: AppLanguage) -> Bundle? {
        let root = resources.resourceURL ?? resources.bundleURL
        return Bundle(url: root.appendingPathComponent(language.rawValue.lowercased() + ".lproj"))
            ?? Bundle(url: root.appendingPathComponent(language.rawValue + ".lproj"))
    }

    private static let english = languageBundle(.english) ?? resources
}

/// Shared runtime language. SwiftUI tracks reads; background services can safely read it too.
public enum L10n {
    private final class State: Observable, @unchecked Sendable {
        private let registrar = ObservationRegistrar()
        private let lock = NSLock()
        private var value = Localizer(language: ProcessInfo.processInfo.environment["TANGLER_LANGUAGE"]
            .flatMap(AppLanguage.init(rawValue:)) ?? .system)

        var localizer: Localizer {
            get {
                registrar.access(self, keyPath: \.localizer)
                return lock.withLock { value }
            }
            set {
                // Notify outside the lock: observers may read the current language again.
                registrar.withMutation(of: self, keyPath: \.localizer) {
                    lock.withLock { value = newValue }
                }
            }
        }
    }
    private static let state = State()

    public static var current: Localizer { state.localizer }

    @MainActor public static func configure(_ language: AppLanguage) {
        let localizer = Localizer(language: language)
        guard current.language != localizer.language else { return }
        state.localizer = localizer
    }

    public static func text(_ key: String, _ arguments: String...) -> String {
        let localizer = current
        return arguments.isEmpty ? localizer.text(key) : localizer.format(key, arguments)
    }

    public static func count(_ key: String, _ count: Int) -> String { current.count(key, count) }
}
