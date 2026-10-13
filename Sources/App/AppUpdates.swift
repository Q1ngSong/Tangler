import CoreKit
import AppKit
import Combine
import Observation
import Sparkle

/// Sparkle owns downloading, signature verification, preferences and installation.
@MainActor @Observable
final class AppUpdates: NSObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    private(set) var isConfigured = false
    private(set) var canCheckForUpdates = false
    private(set) var automaticallyChecksForUpdates = false
    private(set) var automaticallyDownloadsUpdates = false
    private(set) var lastUpdateCheckDate: Date?
    private(set) var checkStatus: AppUpdateStatus = .idle
    private(set) var availableVersion: String?
    private(set) var startupProblem: String?
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: Set<AnyCancellable> = []
    @ObservationIgnored private let beforeRelaunch: @MainActor () async -> Void

    init(beforeRelaunch: @escaping @MainActor () async -> Void) {
        self.beforeRelaunch = beforeRelaunch
        super.init()
    }

    func start() {
        guard controller == nil, Self.isConfigurationValid(Bundle.main.infoDictionary ?? [:]) else { return }
        isConfigured = true
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        let updater = controller.updater
        updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] value in self?.canCheckForUpdates = value }.store(in: &observations)
        updater.publisher(for: \.automaticallyChecksForUpdates)
            .sink { [weak self] value in self?.automaticallyChecksForUpdates = value }.store(in: &observations)
        updater.publisher(for: \.automaticallyDownloadsUpdates)
            .sink { [weak self] value in self?.automaticallyDownloadsUpdates = value }.store(in: &observations)
        updater.publisher(for: \.lastUpdateCheckDate)
            .sink { [weak self] value in self?.lastUpdateCheckDate = value }.store(in: &observations)
        updater.publisher(for: \.sessionInProgress)
            .sink { [weak self] active in
                guard let self else { return }
                if active { self.checkStatus = .checking }
                else if self.checkStatus == .checking { self.checkStatus = .idle }
            }.store(in: &observations)
        do { try updater.start() }
        catch { startupProblem = L10n.text("app.the.update.service.is.unavailable", String(describing: (error.localizedDescription))) }
    }

    static func isConfigurationValid(_ info: [String: Any]) -> Bool {
        guard let feed = info["SUFeedURL"] as? String, let url = URL(string: feed),
              url.scheme == "https", url.host != nil,
              let key = info["SUPublicEDKey"] as? String,
              let bytes = Data(base64Encoded: key), bytes.count == 32 else { return false }
        return true
    }

    var updateMode: AppUpdateMode {
        AppUpdateMode(checks: automaticallyChecksForUpdates, downloads: automaticallyDownloadsUpdates)
    }

    func setUpdateMode(_ mode: AppUpdateMode) {
        guard let updater = controller?.updater, startupProblem == nil else { return }
        mode.apply(to: updater)
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        controller?.checkForUpdates(nil)
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        availableVersion = item.displayVersionString
        checkStatus = .available(item.displayVersionString)
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        checkStatus = .downloaded(item.displayVersionString)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        if let result = AppUpdateStatus.result(for: error) { checkStatus = result }
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if let error, let result = AppUpdateStatus.result(for: error) { checkStatus = result }
        else if checkStatus == .checking { checkStatus = .idle }
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        // Background checks stay in the menu/settings instead of interrupting another app.
        availableVersion = update.displayVersionString
        return immediateFocus
    }

    func standardUserDriverWillFinishUpdateSession() { availableVersion = nil }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock install: @escaping () -> Void) -> Bool {
        Task {
            await beforeRelaunch()
            install()
        }
        return true
    }
}

/// Both flags belong to Sparkle's host preferences, including changes made by its own dialogs.
enum AppUpdateMode: String, CaseIterable, Identifiable {
    case manual, notify, automatic
    var id: Self { self }
    var title: String {
        switch self {
        case .manual: L10n.text("app.check.manually")
        case .notify: L10n.text("app.check.automatically.and.notify")
        case .automatic: L10n.text("app.download.and.install.automatically")
        }
    }
    var detail: String {
        switch self {
        case .manual: L10n.text("app.look.for.updates.only.when.you.click")
        case .notify: L10n.text("app.check.about.every.hours.while.tangler.is")
        case .automatic: L10n.text("app.check.for.and.download.updates.automatically.usually")
        }
    }

    init(checks: Bool, downloads: Bool) {
        self = checks ? (downloads ? .automatic : .notify) : .manual
    }

    @MainActor func apply(to updater: SPUUpdater) {
        // Enable checks first: Sparkle only permits automatic installation when checks are on.
        if self == .manual {
            updater.automaticallyDownloadsUpdates = false
            updater.automaticallyChecksForUpdates = false
        } else {
            updater.automaticallyChecksForUpdates = true
            updater.automaticallyDownloadsUpdates = self == .automatic
        }
    }
}

enum AppUpdateStatus: Equatable {
    case idle, checking, current
    case available(String), downloaded(String), noCompatibleUpdate(String), failed(String)

    var message: String {
        switch self {
        case .idle: L10n.text("app.check.for.a.newer.version")
        case .checking: L10n.text("app.checking.for.updates")
        case .current: L10n.text("app.you.re.up.to.date")
        case .available(let version): L10n.text("app.version.is.available", String(describing: (version)))
        case .downloaded(let version): L10n.text("app.version.has.been.downloaded", String(describing: (version)))
        case .noCompatibleUpdate(let reason): reason
        case .failed(let reason): L10n.text("app.update.check.or.download.failed", String(describing: (reason)))
        }
    }
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }

    static func result(for error: Error) -> Self? {
        let error = error as NSError
        guard error.domain == SUSparkleErrorDomain else { return .failed(error.localizedDescription) }
        switch error.code {
        case Int(SUError.noUpdateError.rawValue):
            let reason = (error.userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?.int32Value
            if reason == SPUNoUpdateFoundReason.onLatestVersion.rawValue { return .current }
            if reason == SPUNoUpdateFoundReason.onNewerThanLatestVersion.rawValue {
                return .noCompatibleUpdate(L10n.text("app.this.version.is.newer.than.the.latest"))
            }
            // An empty feed, unsupported OS or unsupported CPU does not mean the App is up to date.
            return .noCompatibleUpdate(L10n.text("app.no.update.is.compatible.with.this.mac", String(describing: (error.localizedDescription))))
        case Int(SUError.installationCanceledError.rawValue), Int(SUError.installationAuthorizeLaterError.rawValue):
            return nil
        default:
            return .failed(error.localizedDescription)
        }
    }
}
