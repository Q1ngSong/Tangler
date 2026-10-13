import ApplicationServices
import Foundation

extension AXFailure {
    /// nil for success.
    init?(_ error: AXError) {
        switch error {
        case .success: return nil
        case .apiDisabled: self = .apiDisabled
        case .cannotComplete: self = .cannotComplete
        case .invalidUIElement: self = .invalidElement
        case .attributeUnsupported, .actionUnsupported, .notImplemented, .parameterizedAttributeUnsupported, .noValue:
            self = .unsupported
        default: self = .other(error.rawValue)
        }
    }
}

/// Small typed wrappers around the Accessibility C API.
enum AXRead {
    /// Every call gives up after this long, so one unresponsive app cannot stall the rest
    /// (design section 5.3).
    static let timeout: Float = 0.15

    static func application(_ pid: Int32) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, timeout)
        return element
    }

    static func value(_ element: AXUIElement, _ attribute: String) -> Result<CFTypeRef, AXFailure> {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        if let failure = AXFailure(error) { return .failure(failure) }
        guard let value else { return .failure(.unsupported) }
        return .success(value)
    }

    static func attribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        try? value(element, attribute).get()
    }

    /// Several attributes in one round trip; an attribute that failed reads as nil.
    static func attributes(_ element: AXUIElement, _ names: [String]) -> Result<[CFTypeRef?], AXFailure> {
        var values: CFArray?
        let error = AXUIElementCopyMultipleAttributeValues(element, names as CFArray, [], &values)
        if let failure = AXFailure(error) { return .failure(failure) }
        guard let list = values as [AnyObject]?, list.count == names.count else { return .failure(.unsupported) }
        return .success(list.map { value in
            if CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetType(value as! AXValue) == .axError { return nil }
            return value
        })
    }

    static func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func string(_ value: CFTypeRef?) -> String? { value as? String }
    static func bool(_ value: CFTypeRef?) -> Bool? { value as? Bool }

    static func point(_ value: CFTypeRef?) -> CGPoint? {
        var point = CGPoint.zero
        guard let value, CFGetTypeID(value) == AXValueGetTypeID(),
              AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    static func size(_ value: CFTypeRef?) -> CGSize? {
        var size = CGSize.zero
        guard let value, CFGetTypeID(value) == AXValueGetTypeID(),
              AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    static func frame(of element: AXUIElement) -> Result<CGRect, AXFailure> {
        switch attributes(element, [kAXPositionAttribute, kAXSizeAttribute]) {
        case .failure(let failure): return .failure(failure)
        case .success(let values):
            guard let origin = point(values[0]), let size = size(values[1]) else { return .failure(.unsupported) }
            return .success(CGRect(origin: origin, size: size))
        }
    }

    static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success && settable.boolValue
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> AXFailure? {
        AXFailure(AXUIElementSetAttributeValue(element, attribute as CFString, value))
    }
}
