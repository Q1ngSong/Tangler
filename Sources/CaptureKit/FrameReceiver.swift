import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

/// Forwards an SCStream's new frames as images, and its end, to a sink.
final class FrameReceiver: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "app.local.tangler.capture-frames", qos: .userInitiated)
    private let sink: LiveCaptureSink
    private let lock = NSLock()
    private var active = true

    init(sink: LiveCaptureSink) {
        self.sink = sink
    }

    /// Stops forwarding. Returns false if forwarding had already stopped.
    @discardableResult
    func deactivate() -> Bool {
        lock.withLock {
            defer { active = false }
            return active
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, lock.withLock({ active }), let buffer = Self.newFrame(in: sampleBuffer),
              let image = PixelBufferImage.makeImage(from: buffer) else { return }
        sink.frame(image)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        if deactivate() { sink.ended() }
    }

    /// The image of a sample that carries a new frame. Idle samples mean the window did not
    /// change, so the consumer keeps showing the previous frame.
    private static func newFrame(in sampleBuffer: CMSampleBuffer) -> CVPixelBuffer? {
        guard sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus),
              status == .complete || status == .started else { return nil }
        return CMSampleBufferGetImageBuffer(sampleBuffer)
    }
}
