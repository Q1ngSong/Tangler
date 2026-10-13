import CoreGraphics

/// Pixel dimensions of a captured image.
struct PixelSize: Equatable, Sendable {
    var width: Int
    var height: Int
}

/// Sizes and rates for thumbnails and live frames.
enum CaptureGeometry {
    /// Larger than any display; the cap also keeps the size arithmetic within `Int`.
    static let largestPixelSize = 16_384

    static func clampedMaxPixelSize(_ value: Int) -> Int { min(max(value, 1), largestPixelSize) }

    static func clampedFramesPerSecond(_ value: Int) -> Int { min(max(value, 1), 30) }

    /// The window's size in pixels, scaled down so the long edge fits `maxPixelSize`.
    /// Never larger than the window's own pixels; nil when the window has no area.
    static func outputSize(pointSize: CGSize, pixelScale: CGFloat, maxPixelSize: Int) -> PixelSize? {
        let scale = pixelScale.isFinite && pixelScale > 0 ? pixelScale : 1
        let width = Double(pointSize.width * scale)
        let height = Double(pointSize.height * scale)
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        let limit = clampedMaxPixelSize(maxPixelSize)
        let factor = min(1, Double(limit) / max(width, height))
        func side(_ length: Double) -> Int { min(limit, max(1, Int((length * factor).rounded()))) }
        return PixelSize(width: side(width), height: side(height))
    }

    /// At nominal resolution ScreenCaptureKit samples one pixel per point; an output with
    /// more pixels than the window has points would come out blurry without native sampling.
    static func needsNativeResolution(pointSize: CGSize, output: PixelSize) -> Bool {
        CGFloat(max(output.width, output.height)) > max(pointSize.width, pointSize.height)
    }
}
