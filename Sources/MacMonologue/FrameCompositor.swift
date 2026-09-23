import CoreImage
import CoreVideo
import Foundation
import Metal

/// Renders what gets recorded: the camera on its own, optionally mirrored, or —
/// in screen mode — the screen with the camera as a round bubble on top.
///
/// Mirroring for the *recording* happens here rather than through
/// `AVCaptureConnection.isVideoMirrored`: this is an image transform that
/// verifiably flips pixels, whereas whether the connection property does so for a
/// data output (rather than only hinting a display) is not something to bet a
/// feature on.
///
/// Not thread-safe; confined to the capture output queue.
final class FrameCompositor {
    private let context: CIContext
    private var pool: PixelBufferPool?
    private let colorSpace = CGColorSpace(name: CGColorSpace.itur_709)!

    init() {
        let options: [CIContextOption: Any] = [
            .cacheIntermediates: false,
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        ]
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: options)
        } else {
            context = CIContext(options: options)
        }
    }

    var exhaustedCount: Int { pool?.exhaustedCount ?? 0 }

    /// Camera mode: the camera fills the frame, mirrored or not.
    func renderCamera(_ camera: CVPixelBuffer, mirrored: Bool) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(camera)
        let height = CVPixelBufferGetHeight(camera)
        var image = CIImage(cvPixelBuffer: camera)
        if mirrored { image = Self.mirrored(image) }
        return render(image, width: width, height: height)
    }

    // MARK: - Internals

    private func render(_ image: CIImage, width: Int, height: Int) -> CVPixelBuffer? {
        if pool?.width != width || pool?.height != height {
            pool = PixelBufferPool(width: width, height: height)
        }
        guard let output = pool?.makeBuffer() else { return nil }
        context.render(
            image,
            to: output,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            colorSpace: colorSpace
        )
        return output
    }

    /// Flips horizontally about the image's own extent, so it stays in place.
    static func mirrored(_ image: CIImage) -> CIImage {
        let extent = image.extent
        return image.transformed(by: CGAffineTransform(scaleX: -1, y: 1)
            .translatedBy(x: -(extent.origin.x * 2 + extent.width), y: 0))
    }
}
