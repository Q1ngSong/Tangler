import CoreGraphics

/// Window thumbnails. Implemented by CaptureKit, the only module allowed to use
/// ScreenCaptureKit (design section 3.3).
public protocol CaptureService: AnyObject, Sendable {
    /// Screen Recording permission; without it requests return nil or an empty stream.
    var isAuthorized: Bool { get }
    func thumbnail(of id: WindowID, maxPixelSize: Int) async -> CGImage?
    /// Live frames until the consumer stops iterating. The stream ends early when the window
    /// cannot be captured or the system stops capturing; callers then fall back to `thumbnail`.
    func liveFrames(of id: WindowID, maxPixelSize: Int, framesPerSecond: Int) -> AsyncStream<CGImage>
}

public extension CaptureService {
    /// The defaults from design section 3.3: 15 frames per second, long edge 800 pixels.
    func liveFrames(of id: WindowID) -> AsyncStream<CGImage> {
        liveFrames(of: id, maxPixelSize: 800, framesPerSecond: 15)
    }
}
