import Contracts
import CoreKit

/// What the modules started so far offer the ones that start after them.
struct SharedServices {
    var placement: (any PlacementService)?
    var tabGroups: (any TabGroupService)?
    /// Looked up when it is needed: the module that offers it (Workspaces) starts after the
    /// ones that use it.
    var desktopOwnership: @MainActor () -> (any DesktopOwnership)? = { nil }
}

/// Starts feature modules in dependency order and stops them in reverse (design section 3.6).
/// A module that fails to start is recorded, cleaned up and skipped; the others keep running.
@MainActor
final class ModuleRunner {
    private(set) var running: [any FeatureModule] = []
    private(set) var failures: [ModuleID: String] = [:]
    private var desktopOwnership: (any DesktopOwnership)?
    private let log = DiagnosticLog("app")

    /// Modules without required services start first, so providers such as WindowLayout's
    /// placement service exist before the modules that use them.
    /// TabGroups requires nothing, so it starts before Workspaces, which uses its tab groups.
    static func startOrder(_ types: [any FeatureModule.Type]) -> [any FeatureModule.Type] {
        types.filter { $0.requiredServices.isEmpty } + types.filter { !$0.requiredServices.isEmpty }
    }

    func start(_ types: [any FeatureModule.Type], isEnabled: (ModuleID) -> Bool,
               makeContext: (SharedServices) -> ModuleContext) async {
        var shared = SharedServices()
        shared.desktopOwnership = { [weak self] in self?.desktopOwnership }
        for type in Self.startOrder(types) where isEnabled(type.moduleID) {
            let module = type.init(context: makeContext(shared))
            do {
                try await module.start()
            } catch {
                failures[type.moduleID] = String(describing: error)
                log.problem("模块 \(type.moduleID.rawValue) 启动失败：\(error)")
                await module.stop()
                continue
            }
            log.note("模块 \(type.moduleID.rawValue) 已启动")
            running.append(module)
            for service in module.providedServices() {
                switch service {
                case .placement(let provided): shared.placement = provided
                case .tabGroups(let provided): shared.tabGroups = provided
                case .desktopOwnership(let provided): desktopOwnership = provided
                }
            }
        }
    }

    func stop() async {
        desktopOwnership = nil
        for module in running.reversed() { await module.stop() }
        running.removeAll()
    }
}
