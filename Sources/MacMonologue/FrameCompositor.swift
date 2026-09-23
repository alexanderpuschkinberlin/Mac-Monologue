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

    /// Camera mode: the camera fills the frame, mirrored or not, and zoomed to
    /// `crop` — a normalised, top-left window — when following a face.
    func renderCamera(_ camera: CVPixelBuffer, mirrored: Bool, crop: CGRect? = nil) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(camera)
        let height = CVPixelBufferGetHeight(camera)
        var image = Self.framed(CIImage(cvPixelBuffer: camera), to: crop)
        if mirrored { image = Self.mirrored(image) }
        return render(image, width: width, height: height)
    }

    /// The part of `image` inside `crop`, scaled up to fill the image's own extent.
    static func framed(_ image: CIImage, to crop: CGRect?) -> CIImage {
        guard let crop, crop.width > 0, crop.height > 0 else { return image }
        let extent = image.extent
        // Normalised top-left → Core Image pixels, bottom-left.
        let window = CGRect(x: extent.minX + crop.minX * extent.width,
                            y: extent.minY + (1 - crop.maxY) * extent.height,
                            width: crop.width * extent.width,
                            height: crop.height * extent.height)
        return image.cropped(to: window)
            .transformed(by: CGAffineTransform(translationX: -window.minX, y: -window.minY))
            .transformed(by: CGAffineTransform(scaleX: extent.width / window.width,
                                               y: extent.height / window.height))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
    }

    /// Screen mode: the screen fills the canvas, the camera sits on top as a
    /// circle in `bubble` — a pixel rect, origin top-left. With no camera, or an
    /// empty bubble rect, the screen is rendered alone.
    func renderScreen(
        screen: CVPixelBuffer?,
        camera: CVPixelBuffer?,
        canvasWidth: Int,
        canvasHeight: Int,
        bubble: CGRect,
        mirrorsCamera: Bool,
        cameraCrop: CGRect? = nil
    ) -> CVPixelBuffer? {
        let canvas = CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)

        var background = CIImage(color: .black).cropped(to: canvas)
        if let screen {
            var image = CIImage(cvPixelBuffer: screen)
            let extent = image.extent
            if extent.size != canvas.size, extent.width > 0, extent.height > 0 {
                image = image.transformed(by: CGAffineTransform(
                    scaleX: canvas.width / extent.width, y: canvas.height / extent.height))
            }
            background = image.composited(over: background)
        }

        var result = background
        if let camera, bubble.width >= 2 {
            result = Self.bubble(camera: Self.framed(CIImage(cvPixelBuffer: camera), to: cameraCrop), in: bubble,
                                 canvasHeight: canvas.height, mirrored: mirrorsCamera)
                .applyingFilter("CIBlendWithAlphaMask", parameters: [
                    kCIInputBackgroundImageKey: background,
                    kCIInputMaskImageKey: circleMask(diameter: Int(bubble.width))
                        .transformed(by: Self.placement(of: bubble, canvasHeight: canvas.height)),
                ])
        }
        return render(result.cropped(to: canvas), width: canvasWidth, height: canvasHeight)
    }

    // MARK: - Bubble

    private var masks: [Int: CIImage] = [:]

    /// A white disc with an antialiased edge, transparent outside. Built once per
    /// diameter, not per frame.
    private func circleMask(diameter: Int) -> CIImage {
        if let cached = masks[diameter] { return cached }
        let radius = CGFloat(diameter) / 2
        let mask = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: radius, y: radius),
            "inputRadius0": max(0, radius - 1.5),
            "inputRadius1": radius,
            "inputColor0": CIColor.white,
            "inputColor1": CIColor.clear,
        ])!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        masks[diameter] = mask
        return mask
    }

    /// The camera, cropped to a centred square, scaled to the bubble, optionally
    /// mirrored, and moved to its place on the canvas.
    private static func bubble(camera: CIImage, in rect: CGRect, canvasHeight: CGFloat,
                               mirrored: Bool) -> CIImage {
        let extent = camera.extent
        let side = min(extent.width, extent.height)
        let square = CGRect(x: extent.midX - side / 2, y: extent.midY - side / 2, width: side, height: side)

        var image = camera.cropped(to: square)
            .transformed(by: CGAffineTransform(translationX: -square.minX, y: -square.minY))
            .transformed(by: CGAffineTransform(scaleX: rect.width / side, y: rect.width / side))
        if mirrored { image = Self.mirrored(image) }
        return image.transformed(by: placement(of: rect, canvasHeight: canvasHeight))
    }

    /// From a top-left pixel rect to Core Image's bottom-left coordinates.
    private static func placement(of rect: CGRect, canvasHeight: CGFloat) -> CGAffineTransform {
        CGAffineTransform(translationX: rect.minX, y: canvasHeight - rect.maxY)
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
