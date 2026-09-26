import CoreImage
import CoreVideo
import Foundation
import Metal
import Vision

/// Cuts the person out of the camera picture: a mask, white where the person
/// is, in the camera's own pixels.
///
/// Two ways, chosen per frame. With a green screen, by colour - sharp edges,
/// almost free on the GPU. Without, by Apple's person segmentation - works in
/// any room, softer at the hair, and run every other frame to keep it cheap.
/// In automatic mode the edges of the picture decide, a few times a second.
///
/// Not thread-safe; confined to the capture output queue.
final class PersonKeyer {
    enum Method: Equatable, Sendable { case greenScreen, segmentation }

    struct Key {
        let mask: CIImage
        /// The colours with the green glow taken off; the plain camera otherwise.
        let camera: CIImage
        let method: Method
    }

    private let maskCube = ChromaKey.maskCube()
    private let despillCube = ChromaKey.despillCube()
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let sampler: CIContext

    private var detector = GreenScreenDetector()
    private var frame = 0
    private var lastSegmentation: CIImage?

    /// How often automatic mode looks at the edges; about twice a second at 30 fps.
    static let framesPerDetection = 15
    /// Segmentation runs on every other frame; the mask in between is the last one.
    static let framesPerSegmentation = 2

    init() {
        let options: [CIContextOption: Any] = [.cacheIntermediates: false]
        if let device = MTLCreateSystemDefaultDevice() {
            sampler = CIContext(mtlDevice: device, options: options)
        } else {
            sampler = CIContext(options: options)
        }
    }

    func key(_ buffer: CVPixelBuffer, choice: KeyingChoice) -> Key {
        frame += 1
        let camera = CIImage(cvPixelBuffer: buffer)

        let method: Method
        switch choice {
        case .greenScreen: method = .greenScreen
        case .segmentation: method = .segmentation
        case .automatic:
            if frame % Self.framesPerDetection == 1 { detector.observe(borderSamples(of: camera)) }
            method = detector.isGreen ? .greenScreen : .segmentation
        }

        switch method {
        case .greenScreen:
            lastSegmentation = nil
            let mask = camera.applyingFilter("CIColorCubeWithColorSpace", parameters: [
                "inputCubeDimension": ChromaKey.cubeSize,
                "inputCubeData": maskCube,
                "inputColorSpace": colorSpace,
            ])
            let clean = camera.applyingFilter("CIColorCubeWithColorSpace", parameters: [
                "inputCubeDimension": ChromaKey.cubeSize,
                "inputCubeData": despillCube,
                "inputColorSpace": colorSpace,
            ])
            return Key(mask: mask.cropped(to: camera.extent), camera: clean.cropped(to: camera.extent),
                       method: .greenScreen)
        case .segmentation:
            if lastSegmentation == nil || frame % Self.framesPerSegmentation == 0,
               let fresh = segment(buffer, extent: camera.extent) {
                lastSegmentation = fresh
            }
            let mask = lastSegmentation ?? CIImage(color: .white).cropped(to: camera.extent)
            return Key(mask: mask, camera: camera, method: .segmentation)
        }
    }

    /// Apple's person segmentation, scaled to the camera and softened a hair so
    /// the edge does not shimmer between frames.
    private func segment(_ buffer: CVPixelBuffer, extent: CGRect) -> CIImage? {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        try? VNImageRequestHandler(cvPixelBuffer: buffer, options: [:]).perform([request])
        guard let result = request.results?.first?.pixelBuffer else { return nil }
        let raw = CIImage(cvPixelBuffer: result)
        let scaled = raw.transformed(by: CGAffineTransform(scaleX: extent.width / raw.extent.width,
                                                           y: extent.height / raw.extent.height))
        return scaled.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 1.5])
            .cropped(to: extent)
    }

    /// The top, left and right edges of a small copy of the picture - where the
    /// background shows, and the person usually does not.
    private func borderSamples(of camera: CIImage) -> [(r: Double, g: Double, b: Double)] {
        let width = 48, height = 27
        let small = camera.transformed(by: CGAffineTransform(scaleX: CGFloat(width) / camera.extent.width,
                                                             y: CGFloat(height) / camera.extent.height))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        sampler.render(small, toBitmap: &pixels, rowBytes: width * 4,
                       bounds: CGRect(x: 0, y: 0, width: width, height: height),
                       format: .RGBA8, colorSpace: colorSpace)
        var samples: [(r: Double, g: Double, b: Double)] = []
        for y in 0..<height {
            for x in 0..<width where y < 4 || x < 5 || x >= width - 5 {
                let i = (y * width + x) * 4
                samples.append((Double(pixels[i]) / 255, Double(pixels[i + 1]) / 255, Double(pixels[i + 2]) / 255))
            }
        }
        return samples
    }
}
