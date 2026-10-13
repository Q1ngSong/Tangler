import Contracts
import CoreGraphics
import CoreMedia
import CoreVideo
import ScreenCaptureKit

/// A window as ScreenCaptureKit lists it.
struct ShareableWindow: CapturableWindow, @unchecked Sendable {
    // SCWindow is an immutable snapshot, so handing it between threads is safe.
    let window: SCWindow
    var windowID: WindowID { WindowID(rawValue: window.windowID) }
}

enum CaptureBackendError: Error {
    case notAShareableWindow
    case windowHasNoArea
}

/// The CaptureBackend built on ScreenCaptureKit.
struct ScreenCaptureBackend: CaptureBackend {
    var isAuthorized: Bool { CGPreflightScreenCaptureAccess() }

    func shareableWindows() async throws -> [any CapturableWindow] {
        // Off-screen windows include those on other Spaces and minimized ones.
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        return content.windows.map(ShareableWindow.init)
    }

    func captureImage(of window: any CapturableWindow, maxPixelSize: Int) async throws -> CGImage {
        let (filter, configuration) = try Self.captureSetup(for: window, maxPixelSize: maxPixelSize)
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    func startLiveCapture(of window: any CapturableWindow, maxPixelSize: Int, framesPerSecond: Int,
                          sink: LiveCaptureSink) async throws -> any LiveCapture {
        let (filter, configuration) = try Self.captureSetup(for: window, maxPixelSize: maxPixelSize)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(framesPerSecond))
        // The fewest buffers ScreenCaptureKit allows; each frame is copied out at once.
        configuration.queueDepth = 3
        return try await LiveWindowCapture.start(filter: filter, configuration: configuration, sink: sink)
    }

    /// The filter and configuration shared by screenshots and live captures.
    private static func captureSetup(for window: any CapturableWindow,
                                     maxPixelSize: Int) throws -> (SCContentFilter, SCStreamConfiguration) {
        guard let window = (window as? ShareableWindow)?.window else { throw CaptureBackendError.notAShareableWindow }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let points = window.frame.size
        guard let size = CaptureGeometry.outputSize(pointSize: points, pixelScale: CGFloat(filter.pointPixelScale),
                                                    maxPixelSize: maxPixelSize) else {
            throw CaptureBackendError.windowHasNoArea
        }
        let configuration = SCStreamConfiguration()
        configuration.width = size.width
        configuration.height = size.height
        configuration.captureResolution = CaptureGeometry.needsNativeResolution(pointSize: points, output: size)
            ? .best : .nominal
        configuration.scalesToFit = true
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        // Show the whole window even when part of it hangs off the screen.
        configuration.ignoreGlobalClipSingleWindow = true
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        return (filter, configuration)
    }
}
