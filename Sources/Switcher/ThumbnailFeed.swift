import Contracts
import CoreGraphics

/// Pictures for the cards: one still per window, and live frames for the window being
/// followed (the selection). Without Screen Recording permission it asks for nothing and
/// the cards show the app icon and title instead.
@MainActor
final class ThumbnailFeed {
    typealias Deliver = @MainActor (_ id: WindowID, _ image: CGImage, _ live: Bool) -> Void
    typealias Pause = @MainActor (Duration) async -> Void

    /// A stream starts only once the selection rests this long; stepping through the list
    /// with Tab would otherwise start and stop a capture stream for every window passed.
    static let settleDelay: Duration = .milliseconds(150)

    private let capture: any CaptureService
    private let pixelSize: Int
    private let pause: Pause
    private let deliver: Deliver
    private var stills: Task<Void, Never>?
    private var live: Task<Void, Never>?
    private var followed: WindowID?

    init(capture: any CaptureService, pixelSize: Int, pause: @escaping Pause, deliver: @escaping Deliver) {
        self.capture = capture
        self.pixelSize = pixelSize
        self.pause = pause
        self.deliver = deliver
    }

    /// One still per window, requested one after another in this order.
    func loadStills(_ ids: [WindowID]) {
        stills?.cancel()
        guard capture.isAuthorized else { return }
        stills = Task { [capture, pixelSize, deliver] in
            for id in ids {
                let image = await capture.thumbnail(of: id, maxPixelSize: pixelSize)
                guard !Task.isCancelled else { return }
                if let image { deliver(id, image, false) }
            }
        }
    }

    /// Streams `id` once it stays followed for `settleDelay`; nil stops streaming.
    func follow(_ id: WindowID?) {
        guard id != followed else { return }
        live?.cancel()
        followed = id
        guard let id, capture.isAuthorized else { return }
        live = Task { [capture, pixelSize, pause, deliver] in
            await pause(Self.settleDelay)
            guard !Task.isCancelled else { return }
            var received = false
            // Leaving the loop, by cancellation included, ends the stream and its capture.
            for await frame in capture.liveFrames(of: id) {
                guard !Task.isCancelled else { return }
                received = true
                deliver(id, frame, true)
            }
            // The stream ended by itself before any frame: the window cannot be streamed.
            guard !received, !Task.isCancelled else { return }
            let image = await capture.thumbnail(of: id, maxPixelSize: pixelSize)
            if let image, !Task.isCancelled { deliver(id, image, false) }
        }
    }

    func stop() {
        stills?.cancel()
        live?.cancel()
        stills = nil
        live = nil
        followed = nil
    }
}
