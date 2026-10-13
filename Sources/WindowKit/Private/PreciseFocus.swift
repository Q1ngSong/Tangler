import ApplicationServices
import Contracts
import CoreGraphics

/// Brings one specific window forward and makes it key, even on another Space, through the
/// window server calls the Dock uses (as AltTab and Hammerspoon do). The public fallback
/// activates the app and raises the window through Accessibility.
struct PreciseFocus: @unchecked Sendable {
    private typealias SetFrontProcess = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UInt32, UInt32) -> CGError
    private typealias PostEventRecord = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>,
                                                        UnsafeMutablePointer<UInt8>) -> CGError
    private typealias ProcessForPID = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    /// Marks the request as user generated, which lets it switch Spaces.
    private static let userGenerated: UInt32 = 0x200

    private let setFrontProcess: SetFrontProcess
    private let postEventRecord: PostEventRecord
    private let processForPID: ProcessForPID

    init?() {
        guard let setFrontProcess = PrivateSymbols.function(.setFrontProcess, as: SetFrontProcess.self),
              let postEventRecord = PrivateSymbols.function(.postEventRecord, as: PostEventRecord.self),
              let processForPID = PrivateSymbols.function(.processForPID, as: ProcessForPID.self) else { return nil }
        self.setFrontProcess = setFrontProcess
        self.postEventRecord = postEventRecord
        self.processForPID = processForPID
    }

    /// False when the window server refused; the caller then falls back to the public path.
    func focus(_ window: WindowID, pid: Int32) -> Bool {
        var process = ProcessSerialNumber()
        guard processForPID(pid, &process) == 0,
              setFrontProcess(&process, window.rawValue, Self.userGenerated) == .success else { return false }
        makeKey(window, process: &process)
        return true
    }

    /// Where the synthetic press lies: off every display, so no app can take it for a click.
    private static let pressPoint = CGPoint(x: 300_000, y: 300_000)

    // A synthetic window server mouse-down that makes the window key. Record layout from
    // https://github.com/Hammerspoon/hammerspoon/issues/370#issuecomment-545545468. The window
    // server reads 8 bytes past the 0xf8-byte record (crashes reported on macOS 14), so the buffer
    // is 0x100 zeroed bytes. The old NaN point became a click at (0, 0) in some apps (AltTab
    // #5381, macOS 26.3.1), so the point lies far off and only the press is sent, as AltTab does;
    // the press alone makes the window key (checked on macOS 26.6.1, tab groups design 2.1).
    private func makeKey(_ window: WindowID, process: inout ProcessSerialNumber) {
        var bytes = [UInt8](repeating: 0, count: 0x100)
        bytes[0x04] = 0xf8
        bytes[0x08] = 0x01
        bytes[0x3a] = 0x10
        withUnsafeBytes(of: window.rawValue) { raw in
            for (offset, byte) in raw.enumerated() { bytes[0x3c + offset] = byte }
        }
        withUnsafeBytes(of: Self.pressPoint) { raw in
            for (offset, byte) in raw.enumerated() { bytes[0x20 + offset] = byte }
        }
        _ = postEventRecord(&process, &bytes)
    }
}
