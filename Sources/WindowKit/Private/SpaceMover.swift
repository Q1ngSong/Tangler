import Contracts
import Foundation

/// Moves a window to another Space with the bridged operation SkyLight gained in macOS 26.4.
/// It runs in this session only: no injection, no privileges, no SIP changes.
/// Signatures: https://github.com/thatmarcel/macOS-26.4-headers (SkyLight), and the
/// SIP-enabled behaviour discussed in https://github.com/asmvik/yabai/issues/2788
enum SpaceMover {
    private static let className = "SLSBridgedMoveWindowsToManagedSpaceOperation"
    private static let allocSelector = NSSelectorFromString("alloc")
    private static let initSelector = NSSelectorFromString("initWithWindows:spaceID:")
    // Despite the name, this selector takes no argument.
    private static let performSelector = NSSelectorFromString("performWithWMBridgeDelegate")

    private typealias Allocate = @convention(c) (AnyClass, Selector) -> Unmanaged<AnyObject>?
    private typealias Initialize = @convention(c) (AnyObject, Selector, NSArray, UInt64) -> Unmanaged<AnyObject>?
    private typealias Perform = @convention(c) (AnyObject, Selector) -> Void

    /// The class exists and its methods have the signatures the calls below assume.
    static func operationMatches() -> Bool {
        guard let operationClass = NSClassFromString(className),
              let initialize = class_getInstanceMethod(operationClass, initSelector),
              let perform = class_getInstanceMethod(operationClass, performSelector) else { return false }
        return method_getNumberOfArguments(initialize) == 4 && type(of: initialize, argument: nil) == "@"
            && type(of: initialize, argument: 2) == "@" && type(of: initialize, argument: 3) == "Q"
            && method_getNumberOfArguments(perform) == 2 && type(of: perform, argument: nil) == "v"
    }

    /// Starts the move and returns the operation, which must stay alive until the move is
    /// verified; nil when the operation could not be created.
    static func start(moving window: WindowID, to space: SpaceID) -> AnyObject? {
        guard operationMatches(), let operationClass = NSClassFromString(className),
              let allocMethod = class_getClassMethod(operationClass, allocSelector),
              let initMethod = class_getInstanceMethod(operationClass, initSelector),
              let performMethod = class_getInstanceMethod(operationClass, performSelector) else { return nil }
        let allocate = unsafeBitCast(method_getImplementation(allocMethod), to: Allocate.self)
        let initialize = unsafeBitCast(method_getImplementation(initMethod), to: Initialize.self)
        let perform = unsafeBitCast(method_getImplementation(performMethod), to: Perform.self)
        guard let allocated = allocate(operationClass, allocSelector),
              let initialized = initialize(allocated.takeUnretainedValue(), initSelector,
                                           [NSNumber(value: window.rawValue)] as NSArray, space.rawValue) else { return nil }
        // alloc/init hands over one retained reference.
        let operation = initialized.takeRetainedValue()
        perform(operation, performSelector)
        return operation
    }

    private static func type(of method: Method, argument: UInt32?) -> String? {
        let pointer = argument.map { method_copyArgumentType(method, $0) } ?? method_copyReturnType(method)
        guard let pointer else { return nil }
        defer { free(pointer) }
        return String(cString: pointer)
    }
}
