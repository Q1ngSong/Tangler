import ApplicationServices
import CoreGraphics

/// Frame writes through Accessibility.
struct AXFrameBackend: FrameBackend {
    private static let enhancedUserInterface = "AXEnhancedUserInterface"
    let stamps: ReadStamps

    func settable(_ element: AXUIElement) -> (movable: Bool, resizable: Bool) {
        (AXRead.isSettable(element, kAXPositionAttribute), AXRead.isSettable(element, kAXSizeAttribute))
    }

    func frame(of element: AXUIElement) -> Result<CGRect, AXFailure> {
        AXRead.frame(of: element)
    }

    func setSize(_ size: CGSize, of element: AXUIElement) -> AXFailure? {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return .unsupported }
        return AXRead.set(element, kAXSizeAttribute, value)
    }

    func setPosition(_ origin: CGPoint, of element: AXUIElement) -> AXFailure? {
        var origin = origin
        guard let value = AXValueCreate(.cgPoint, &origin) else { return .unsupported }
        return AXRead.set(element, kAXPositionAttribute, value)
    }

    func enhancedUserInterface(pid: Int32) -> Bool? {
        AXRead.bool(AXRead.attribute(AXRead.application(pid), Self.enhancedUserInterface))
    }

    func setEnhancedUserInterface(_ enabled: Bool, pid: Int32) {
        AXRead.set(AXRead.application(pid), Self.enhancedUserInterface, enabled ? kCFBooleanTrue : kCFBooleanFalse)
    }

    func nextStamp() -> UInt64 { stamps.next() }
}
