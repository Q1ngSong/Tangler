import ScreenCaptureKit

/// A running SCStream for one window.
final class LiveWindowCapture: LiveCapture, @unchecked Sendable {
    private let stream: SCStream
    private let receiver: FrameReceiver

    private init(stream: SCStream, receiver: FrameReceiver) {
        self.stream = stream
        self.receiver = receiver
    }

    static func start(filter: SCContentFilter, configuration: SCStreamConfiguration,
                      sink: LiveCaptureSink) async throws -> LiveWindowCapture {
        let receiver = FrameReceiver(sink: sink)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: receiver)
        do {
            try stream.addStreamOutput(receiver, type: .screen, sampleHandlerQueue: receiver.queue)
            try await stream.startCapture()
        } catch {
            receiver.deactivate()
            // A failed start can still hold capture resources.
            try? await stream.stopCapture()
            throw error
        }
        return LiveWindowCapture(stream: stream, receiver: receiver)
    }

    func stop() async {
        // False when already stopped, here or by the system.
        guard receiver.deactivate() else { return }
        try? await stream.stopCapture()
    }
}
