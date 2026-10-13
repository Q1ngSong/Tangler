import SwiftUI

/// Services a module offers to other modules through the App.
public enum ProvidedService {
    case placement(any PlacementService)
    case tabGroups(any TabGroupService)
    case desktopOwnership(any DesktopOwnership)
}

public enum ServiceKind: Hashable, Sendable {
    case placement
}

/// What the App hands every feature module (design section 3.6).
@MainActor
public struct ModuleContext {
    public let windows: any WindowService
    public let input: any InputService
    public let capture: any CaptureService
    public let commands: any CommandRegistry
    public let settings: any SettingsStore
    /// Present only while the module providing it (WindowLayout) is enabled.
    public let placement: (any PlacementService)?
    /// Present only while the module providing it (TabGroups) is enabled.
    public let tabGroups: (any TabGroupService)?
    /// Present only while the module providing it (Workspaces) is running. That module starts
    /// after the ones that use this, so it is looked up each time it is read.
    public var desktopOwnership: (any DesktopOwnership)? { findDesktopOwnership() }
    private let findDesktopOwnership: @MainActor () -> (any DesktopOwnership)?

    public init(windows: any WindowService, input: any InputService, capture: any CaptureService,
                commands: any CommandRegistry, settings: any SettingsStore,
                placement: (any PlacementService)? = nil, tabGroups: (any TabGroupService)? = nil,
                desktopOwnership: @escaping @MainActor () -> (any DesktopOwnership)? = { nil }) {
        self.windows = windows
        self.input = input
        self.capture = capture
        self.commands = commands
        self.settings = settings
        self.placement = placement
        self.tabGroups = tabGroups
        findDesktopOwnership = desktopOwnership
    }
}

/// Implemented by every feature module. The App creates, starts and stops modules;
/// a module never references another feature module directly.
@MainActor
public protocol FeatureModule: AnyObject {
    static var moduleID: ModuleID { get }
    static var displayName: String { get }
    /// Every command the module offers. `start()` registers a handler for each one.
    static var declaredCommands: [CommandSpec] { get }
    /// Names for the module's leader prefixes. `start()` registers each one.
    static var declaredLeaderGroups: [LeaderGroup] { get }
    static var settingsType: (any ModuleSettings.Type)? { get }
    static var requiredServices: Set<ServiceKind> { get }

    init(context: ModuleContext)
    func start() async throws
    func stop() async
    func providedServices() -> [ProvidedService]
    func makeSettingsView() -> AnyView?
}

public extension FeatureModule {
    static var declaredLeaderGroups: [LeaderGroup] { [] }
    static var settingsType: (any ModuleSettings.Type)? { nil }
    static var requiredServices: Set<ServiceKind> { [] }
    func providedServices() -> [ProvidedService] { [] }
    func makeSettingsView() -> AnyView? { nil }
}
