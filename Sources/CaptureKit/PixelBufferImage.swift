import CoreGraphics
import CoreVideo
import Foundation

/// Turns a live capture frame into a CGImage.
enum PixelBufferImage {
    /// Copies a 32-bit BGRA buffer. Copying lets ScreenCaptureKit reuse the buffer at once,
    /// and the image stays valid however long the consumer keeps it.
    static func makeImage(from buffer: CVPixelBuffer) -> CGImage? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
              CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard width > 0, height > 0, let base = CVPixelBufferGetBaseAddress(buffer),
              let provider = CGDataProvider(data: Data(bytes: base, count: bytesPerRow * height) as CFData)
        else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                       space: colorSpace(of: buffer), bitmapInfo: bitmapInfo, provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    private static func colorSpace(of buffer: CVPixelBuffer) -> CGColorSpace {
        if let attached = CVImageBufferGetColorSpace(buffer)?.takeUnretainedValue(), attached.model == .rgb {
            return attached
        }
        return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }
}
