import CoreVideo
import XCTest
@testable import Mac_Monologue

/// Screen mode, on synthetic frames: the bubble lands where `BubbleLayout` says,
/// is round rather than square, and mirrors only itself — never the screen.
final class BubbleCompositingTests: XCTestCase {
    private let canvasWidth = 400
    private let canvasHeight = 200

    private func makeBuffer(width: Int, height: Int,
                            color: (_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8)) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()]
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
                let (r, g, b) = color(x, y)
                row[x * 4] = b; row[x * 4 + 1] = g; row[x * 4 + 2] = r; row[x * 4 + 3] = 255
            }
        }
        return pixelBuffer
    }

    /// (red, green, blue) at a pixel, origin top-left.
    private func pixel(_ buffer: CVPixelBuffer, _ x: Int, _ y: Int) throws -> (r: Int, g: Int, b: Int) {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
        let p = base.advanced(by: y * CVPixelBufferGetBytesPerRow(buffer) + x * 4)
            .assumingMemoryBound(to: UInt8.self)
        return (Int(p[2]), Int(p[1]), Int(p[0]))
    }

    private func isBlue(_ c: (r: Int, g: Int, b: Int)) -> Bool { c.b > 180 && c.r < 70 && c.g < 70 }
    private func isRed(_ c: (r: Int, g: Int, b: Int)) -> Bool { c.r > 180 && c.g < 70 && c.b < 70 }

    private func render(camera: CVPixelBuffer?, corner: BubbleCorner, mirrored: Bool = false)
        throws -> (CVPixelBuffer, CGRect) {
        let screen = try makeBuffer(width: canvasWidth, height: canvasHeight) { _, _ in (0, 0, 255) }
        let bubble = BubbleLayout(corner: corner, size: .large)
            .frame(canvasWidth: canvasWidth, canvasHeight: canvasHeight)
        let output = try XCTUnwrap(FrameCompositor().renderScreen(
            screen: screen, camera: camera, canvasWidth: canvasWidth, canvasHeight: canvasHeight,
            bubble: camera == nil ? .zero : bubble, mirrorsCamera: mirrored))
        return (output, bubble)
    }

    func testOutputIsTheCanvasSize() throws {
        let camera = try makeBuffer(width: 64, height: 48) { _, _ in (255, 0, 0) }
        let (output, _) = try render(camera: camera, corner: .bottomTrailing)
        XCTAssertEqual(CVPixelBufferGetWidth(output), canvasWidth)
        XCTAssertEqual(CVPixelBufferGetHeight(output), canvasHeight)
    }

    func testTheBubbleSitsInEveryCornerItIsPutIn() throws {
        let camera = try makeBuffer(width: 64, height: 48) { _, _ in (255, 0, 0) }
        for corner in BubbleCorner.allCases {
            let (output, bubble) = try render(camera: camera, corner: corner)
            XCTAssertTrue(isRed(try pixel(output, Int(bubble.midX), Int(bubble.midY))),
                          "\(corner): the bubble's centre should show the camera")

            // The opposite corner of the canvas is untouched screen.
            let farX = corner.isLeading ? canvasWidth - 5 : 5
            let farY = corner.isTop ? canvasHeight - 5 : 5
            XCTAssertTrue(isBlue(try pixel(output, farX, farY)), "\(corner): far corner should be screen")
        }
    }

    func testTheBubbleIsRoundNotSquare() throws {
        let camera = try makeBuffer(width: 64, height: 48) { _, _ in (255, 0, 0) }
        let (output, bubble) = try render(camera: camera, corner: .bottomTrailing)
        // Just inside the corner of the bubble's square, but outside its circle.
        XCTAssertTrue(isBlue(try pixel(output, Int(bubble.minX) + 2, Int(bubble.minY) + 2)),
                      "the square's corner must show the screen, not the camera")
    }

    func testWithoutACameraTheScreenIsRecordedAlone() throws {
        let (output, _) = try render(camera: nil, corner: .bottomTrailing)
        let bubble = BubbleLayout(corner: .bottomTrailing, size: .large)
            .frame(canvasWidth: canvasWidth, canvasHeight: canvasHeight)
        XCTAssertTrue(isBlue(try pixel(output, Int(bubble.midX), Int(bubble.midY))))
    }

    /// Mirroring flips the bubble's content and nothing else.
    func testMirroringFlipsTheBubbleOnly() throws {
        // Camera: left half red, right half green.
        let camera = try makeBuffer(width: 64, height: 64) { x, _ in x < 32 ? (255, 0, 0) : (0, 255, 0) }
        let isGreen: ((r: Int, g: Int, b: Int)) -> Bool = { $0.g > 180 && $0.r < 70 && $0.b < 70 }

        let (plain, bubble) = try render(camera: camera, corner: .topLeading)
        let leftOfCentre = (Int(bubble.midX - bubble.width / 4), Int(bubble.midY))
        XCTAssertTrue(isRed(try pixel(plain, leftOfCentre.0, leftOfCentre.1)))

        let (mirrored, _) = try render(camera: camera, corner: .topLeading, mirrored: true)
        XCTAssertTrue(isGreen(try pixel(mirrored, leftOfCentre.0, leftOfCentre.1)))
        XCTAssertTrue(isBlue(try pixel(mirrored, canvasWidth - 5, canvasHeight - 5)),
                      "the screen itself must never be mirrored")
    }
}
