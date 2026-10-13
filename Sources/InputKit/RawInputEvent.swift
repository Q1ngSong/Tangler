import Contracts
import CoreGraphics

/// The parts of a CGEvent that routing reads, as plain values so tests can build them.
struct RawInputEvent: Equatable {
    enum Kind: Equatable {
        case keyDown(keyCode: UInt16, isRepeat: Bool)
        case keyUp(keyCode: UInt16)
        case flagsChanged(keyCode: UInt16)
        case mouseDown(MouseButton)
        case mouseDragged(MouseButton)
        case mouseUp(MouseButton)
        case mouseMoved
        case scroll(delta: CGVector, isContinuous: Bool, isMomentum: Bool)
    }

    var kind: Kind
    var flags: CGEventFlags
    /// Global coordinates, origin at the top-left of the primary display.
    var location: CGPoint

    init(_ kind: Kind, flags: CGEventFlags = [], location: CGPoint = .zero) {
        self.kind = kind
        self.flags = flags
        self.location = location
    }
}
