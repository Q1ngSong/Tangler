import Contracts
import CoreGraphics

/// The module's tab groups for other modules. Requests run on the controller's own queue, and
/// only while the module runs.
final class TabGroupProvider: TabGroupService {
    private let controller: TabsController

    init(controller: TabsController) {
        self.controller = controller
    }

    func groups() async -> [TabGroupSnapshot] {
        await controller.snapshotsInTurn()
    }

    /// A stopped module has no queue, and a request would run at once on a controller that follows
    /// no window. On the main actor, so the module cannot stop between the check and the request
    /// reaching the queue.
    @MainActor
    func form(members: [WindowID], active: WindowID, area: CGRect) async -> Result<TabGroupSnapshot, WindowError> {
        guard controller.isRunning else { return .failure(.unsupported(TabsController.stoppedReason)) }
        return await controller.form(members: members, active: active, area: area)
    }
}
