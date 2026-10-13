/// Told before a desktop is removed, so that what belongs to it is put away first. Implemented by
/// Workspaces and used by WindowLayout, so neither feature module imports the other.
public protocol DesktopOwnership: AnyObject, Sendable {
    /// `space` is about to be removed. A workspace that owns it saves its checkpoint, when
    /// checkpoints are saved automatically, and lets go of the desktop. The removal goes ahead
    /// whatever happened here.
    func desktopWillBeRemoved(_ space: SpaceID) async
}
