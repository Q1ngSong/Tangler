import Contracts
import CoreGraphics

/// Window thumbnails and live frames through ScreenCaptureKit (design section 3.3).
/// A thumbnail is reused for two seconds per window and size limit, so callers may ask
/// again freely. It never asks for Screen Recording permission; without it, thumbnails are
/// nil and live streams end at once. Asking is the App's permission guide's job.
public final class SystemCaptureService: CaptureService {
    let thumbnails: ThumbnailCache
    private let backend: any CaptureBackend
    private let now: @Sendable () -> ContinuousClock.Instant
    private let windows: WindowLookup
    private let purgeRequests: AsyncStream<Void>.Continuation

    public convenience init() {
        self.init(backend: ScreenCaptureBackend())
    }

    init(backend: any CaptureBackend, now: @escaping @Sendable () -> ContinuousClock.Instant = { .now },
         purgeDelay: Duration = .seconds(2)) {
        let thumbnails = ThumbnailCache()
        self.thumbnails = thumbnails
        self.backend = backend
        self.now = now
        windows = WindowLookup(now: now, load: { try await backend.shareableWindows() })
        let (requests, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        purgeRequests = continuation
        // Expired thumbnails are never served again; dropping them returns their memory
        // soon after the switcher or the Dock preview closes.
        Task.detached(priority: .utility) { [weak thumbnails] in
            for await _ in requests {
                repeat {
                    try? await Task.sleep(for: purgeDelay)
                } while (thumbnails?.removeExpired(now: now()) ?? 0) > 0
            }
        }
    }

    deinit {
        purgeRequests.finish()
    }

    public var isAuthorized: Bool { backend.isAuthorized }

    public func thumbnail(of id: WindowID, maxPixelSize: Int) async -> CGImage? {
        guard backend.isAuthorized else { return nil }
        let limit = CaptureGeometry.clampedMaxPixelSize(maxPixelSize)
        if let cached = thumbnails.image(for: id, maxPixelSize: limit, now: now()) { return cached }
        guard let window = await windows.window(id), !Task.isCancelled,
              let image = try? await backend.captureImage(of: window, maxPixelSize: limit) else { return nil }
        thumbnails.insert(image, for: id, maxPixelSize: limit, now: now())
        purgeRequests.yield()
        return image
    }

    /// Only the newest frame waits for a slow consumer. The capture stops when the consumer
    /// cancels, stops iterating or drops the stream. The stream also ends by itself when the
    /// window cannot be captured or the system stops the capture.
    public func liveFrames(of id: WindowID, maxPixelSize: Int, framesPerSecond: Int) -> AsyncStream<CGImage> {
        let (frames, continuation) = AsyncStream.makeStream(of: CGImage.self, bufferingPolicy: .bufferingNewest(1))
        guard backend.isAuthorized else {
            continuation.finish()
            return frames
        }
        let session = LiveSession()
        continuation.onTermination = { _ in session.end() }
        let sink = LiveCaptureSink(frame: { continuation.yield($0) }, ended: { continuation.finish() })
        let limit = CaptureGeometry.clampedMaxPixelSize(maxPixelSize)
        let rate = CaptureGeometry.clampedFramesPerSecond(framesPerSecond)
        session.starting(Task { [backend, windows] in
            guard let window = await windows.window(id), !Task.isCancelled,
                  let capture = try? await backend.startLiveCapture(of: window, maxPixelSize: limit,
                                                                    framesPerSecond: rate, sink: sink) else {
                continuation.finish()
                return
            }
            await session.attach(capture)
        })
        return frames
    }
}
