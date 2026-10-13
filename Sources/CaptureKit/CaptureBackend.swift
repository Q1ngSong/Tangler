import Contracts
import CoreGraphics

/// A window ScreenCaptureKit offers for capture. The system backend wraps its own window
/// object in it; tests use plain values.
protocol CapturableWindow: Sendable {
    var windowID: WindowID { get }
}

/// Where a live capture delivers its output, from any thread.
struct LiveCaptureSink: Sendable {
    var frame: @Sendable (CGImage) -> Void
    /// The system ended the capture, e.g. because the window closed.
    var ended: @Sendable () -> Void
}

/// A running live capture.
protocol LiveCapture: Sendable {
    /// Stops delivering frames; calling it again does nothing.
    func stop() async
}

/// Every ScreenCaptureKit call CaptureKit makes. Kept behind this protocol so unit tests
/// never touch the real framework or trigger the Screen Recording prompt.
protocol CaptureBackend: Sendable {
    /// Screen Recording permission, checked without prompting. Callers check it before every
    /// other call, because listing shareable content without permission shows the prompt.
    var isAuthorized: Bool { get }
    func shareableWindows() async throws -> [any CapturableWindow]
    /// One image whose long edge is at most `maxPixelSize`, without the cursor.
    func captureImage(of window: any CapturableWindow, maxPixelSize: Int) async throws -> CGImage
    /// Frames whose long edge is at most `maxPixelSize`, at most `framesPerSecond` a second.
    func startLiveCapture(of window: any CapturableWindow, maxPixelSize: Int, framesPerSecond: Int,
                          sink: LiveCaptureSink) async throws -> any LiveCapture
}
