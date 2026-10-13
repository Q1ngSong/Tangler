import ApplicationServices
import Contracts

/// The window server number of an Accessibility window, through the private lookup the
/// original app uses. Without it, `WindowMatcher` pairs windows by geometry and title.
struct WindowIdentity: @unchecked Sendable {
    private typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<UInt32>) -> AXError
    private let getWindow: GetWindow

    init?() {
        guard let getWindow = PrivateSymbols.function(.windowForElement, as: GetWindow.self) else { return nil }
        self.getWindow = getWindow
    }

    func windowID(of element: AXUIElement) -> WindowID? {
        var number: UInt32 = 0
        guard getWindow(element, &number) == .success, number != 0 else { return nil }
        return WindowID(rawValue: number)
    }
}
