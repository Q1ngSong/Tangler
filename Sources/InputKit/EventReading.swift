import Contracts
import CoreGraphics

extension RawInputEvent {
    /// Reads the fields routing needs; nil for event types InputKit does not handle.
    init?(_ event: CGEvent, type: CGEventType) {
        let kind: Kind
        switch type {
        case .keyDown:
            kind = .keyDown(keyCode: Self.keyCode(of: event),
                            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        case .keyUp: kind = .keyUp(keyCode: Self.keyCode(of: event))
        case .flagsChanged: kind = .flagsChanged(keyCode: Self.keyCode(of: event))
        case .leftMouseDown: kind = .mouseDown(.left)
        case .leftMouseDragged: kind = .mouseDragged(.left)
        case .leftMouseUp: kind = .mouseUp(.left)
        case .rightMouseDown: kind = .mouseDown(.right)
        case .rightMouseDragged: kind = .mouseDragged(.right)
        case .rightMouseUp: kind = .mouseUp(.right)
        case .otherMouseDown: kind = .mouseDown(.other)
        case .otherMouseDragged: kind = .mouseDragged(.other)
        case .otherMouseUp: kind = .mouseUp(.other)
        case .mouseMoved: kind = .mouseMoved
        case .scrollWheel: kind = Self.scroll(of: event)
        default: return nil
        }
        self.init(kind, flags: event.flags, location: event.location)
    }

    private static func keyCode(of event: CGEvent) -> UInt16 {
        UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
    }

    /// Trackpads and Magic Mouse report points; wheels report lines, one per notch.
    private static func scroll(of event: CGEvent) -> Kind {
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let vertical: CGEventField = continuous ? .scrollWheelEventPointDeltaAxis1 : .scrollWheelEventDeltaAxis1
        let horizontal: CGEventField = continuous ? .scrollWheelEventPointDeltaAxis2 : .scrollWheelEventDeltaAxis2
        let delta = CGVector(dx: event.getDoubleValueField(horizontal), dy: event.getDoubleValueField(vertical))
        return .scroll(delta: delta, isContinuous: continuous,
                       isMomentum: event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0)
    }
}
