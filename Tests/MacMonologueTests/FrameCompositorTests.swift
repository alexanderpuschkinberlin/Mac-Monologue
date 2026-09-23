import CoreImage
import CoreVideo
import XCTest
@testable import Mac_Monologue

/// Proves the mirroring the recording relies on flips actual pixels — which is
/// the whole reason it lives in the compositor rather than on a capture
/// connection, where that was never certain.
final class FrameCompositorTests: XCTestCase {
    /// Left half white, right half black.
    private func makeSplitBuffer(width: Int = 64, height: Int = 32) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ]
        XCTAssertEqual(CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                                           attributes as CFDictionary, &buffer), kCVReturnSuccess)
        let pixelBuffer = try XCTUnwrap(buffer)

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixelBuffer))
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        for y in 0..<height {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                let value: UInt8 = x < width / 2 ? 255 : 0
                row[x * 4 + 0] = value   // B
                row[x * 4 + 1] = value   // G
                row[x * 4 + 2] = value   // R
                row[x * 4 + 3] = 255     // A
            }
        }
        return pixelBuffer
    }

    /// Mean of B, G and R at one pixel.
    private func brightness(_ buffer: CVPixelBuffer, x: Int, y: Int) throws -> Int {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let pixel = base.advanced(by: y * rowBytes + x * 4).assumingMemoryBound(to: UInt8.self)
        return (Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2])) / 3
    }

    func testUnmirroredKeepsLeftAndRight() throws {
        let compositor = FrameCompositor()
        let output = try XCTUnwrap(compositor.renderCamera(try makeSplitBuffer(), mirrored: false))

        XCTAssertGreaterThan(try brightness(output, x: 8, y: 16), 200, "left should stay white")
        XCTAssertLessThan(try brightness(output, x: 56, y: 16), 55, "right should stay black")
    }

    func testMirroredSwapsLeftAndRight() throws {
        let compositor = FrameCompositor()
        let output = try XCTUnwrap(compositor.renderCamera(try makeSplitBuffer(), mirrored: true))

        XCTAssertLessThan(try brightness(output, x: 8, y: 16), 55, "left should now be black")
        XCTAssertGreaterThan(try brightness(output, x: 56, y: 16), 200, "right should now be white")
    }

    func testOutputKeepsTheCameraDimensions() throws {
        let compositor = FrameCompositor()
        let output = try XCTUnwrap(compositor.renderCamera(try makeSplitBuffer(width: 96, height: 54),
                                                            mirrored: true))
        XCTAssertEqual(CVPixelBufferGetWidth(output), 96)
        XCTAssertEqual(CVPixelBufferGetHeight(output), 54)
    }

    func testMirroringKeepsTheImageInPlace() {
        let image = CIImage(color: .white).cropped(to: CGRect(x: 10, y: 20, width: 100, height: 50))
        XCTAssertEqual(FrameCompositor.mirrored(image).extent, image.extent)
    }
}
