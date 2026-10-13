import Contracts
import CoreKit
import Foundation

/// Keeps each module's settings in UserDefaults under `keyPrefix + moduleID`, in the
/// `SettingsCodec` format (design section 3.3).
public final class UserDefaultsSettingsStore: SettingsStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let keyPrefix: String
    private let lock = NSLock()
    private var broadcasters: [ModuleID: Any] = [:]

    public init(defaults: UserDefaults = .standard, keyPrefix: String = "tangler.settings.") {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    /// Never writes the settings back, so unreadable or newer data survives until the next `save`.
    public func load<S: ModuleSettings>(_ type: S.Type) -> S {
        guard let data = defaults.data(forKey: key(for: S.self)) else { return S.defaultValue }
        keepBackup(of: data, for: S.self)
        return (try? SettingsCodec.decode(S.self, from: data)) ?? S.defaultValue
    }

    public func save<S: ModuleSettings>(_ value: S) {
        guard let data = try? SettingsCodec.encode(value) else { return }
        // Storing and sending under one lock keeps concurrent saves in the same order for subscribers.
        locked {
            if let stored = defaults.data(forKey: key(for: S.self)) { keepBackup(of: stored, for: S.self) }
            defaults.set(data, forKey: key(for: S.self))
            broadcasterWhileLocked(for: S.self).send(value)
        }
    }

    public func changes<S: ModuleSettings>(_ type: S.Type) -> AsyncStream<S> {
        locked { broadcasterWhileLocked(for: S.self) }.stream()
    }

    private func key<S: ModuleSettings>(for type: S.Type) -> String { keyPrefix + S.moduleID.rawValue }

    /// A migration is one-way, and a build from before it shows defaults for the migrated data
    /// and then saves over it. So data of an older version is copied as it is to
    /// `<key>.backup.v<version>` before anything newer can replace it; the first copy of a
    /// version is the one kept.
    private func keepBackup<S: ModuleSettings>(of stored: Data, for type: S.Type) {
        guard let version = SettingsCodec.storedVersion(of: stored), version < S.version else { return }
        let backupKey = "\(key(for: S.self)).backup.v\(version)"
        if defaults.object(forKey: backupKey) == nil { defaults.set(stored, forKey: backupKey) }
    }

    private func broadcasterWhileLocked<S: ModuleSettings>(for type: S.Type) -> Broadcaster<S> {
        if let existing = broadcasters[S.moduleID] as? Broadcaster<S> { return existing }
        let created = Broadcaster<S>()
        broadcasters[S.moduleID] = created
        return created
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
