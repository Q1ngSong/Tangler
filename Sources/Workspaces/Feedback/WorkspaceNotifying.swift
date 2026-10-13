/// Shows what saving, opening and releasing did. Commands return as soon as an expansion starts,
/// so the per-entry report reaches the user here.
@MainActor
protocol WorkspaceNotifying: AnyObject {
    /// Called again as the report changes; the last call has `isFinished` set.
    func show(_ report: ExpansionReport)
    func show(message: String)
    func hide()
}
