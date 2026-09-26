import XCTest
@testable import Mac_Monologue

final class ChromaKeyTests: XCTestCase {
    func testGreenScreenIsBackground() {
        XCTAssertEqual(ChromaKey.alpha(r: 0.1, g: 0.8, b: 0.2), 0, accuracy: 0.0001)
        XCTAssertEqual(ChromaKey.alpha(r: 0.0, g: 1.0, b: 0.0), 0, accuracy: 0.0001)
    }

    func testPeopleAndPlainColoursStay() {
        XCTAssertEqual(ChromaKey.alpha(r: 0.85, g: 0.65, b: 0.55), 1, "skin")
        XCTAssertEqual(ChromaKey.alpha(r: 1, g: 1, b: 1), 1, "white")
        XCTAssertEqual(ChromaKey.alpha(r: 0.4, g: 0.4, b: 0.4), 1, "grey")
        XCTAssertEqual(ChromaKey.alpha(r: 0.2, g: 0.2, b: 0.6), 1, "blue shirt")
    }

    func testTheEdgeIsSoft() {
        let halfway = ChromaKey.alpha(r: 0.4, g: 0.4 + (ChromaKey.dominanceStart + ChromaKey.dominanceFull) / 2, b: 0.4)
        XCTAssertGreaterThan(halfway, 0.2)
        XCTAssertLessThan(halfway, 0.8)
    }

    func testDespillTakesTheGreenTintOffOnly() {
        let tinted = ChromaKey.despill(r: 0.5, g: 0.7, b: 0.4)
        XCTAssertEqual(tinted.g, 0.5, accuracy: 0.0001)
        let skin = ChromaKey.despill(r: 0.85, g: 0.65, b: 0.55)
        XCTAssertEqual(skin.g, 0.65, accuracy: 0.0001, "no green lead, nothing to take off")
    }

    func testCubesHaveTheSizeCoreImageExpects() {
        let expected = ChromaKey.cubeSize * ChromaKey.cubeSize * ChromaKey.cubeSize * 4 * MemoryLayout<Float>.size
        XCTAssertEqual(ChromaKey.maskCube().count, expected)
        XCTAssertEqual(ChromaKey.despillCube().count, expected)
    }
}

final class GreenScreenDetectorTests: XCTestCase {
    private let green = (r: 0.15, g: 0.75, b: 0.2)
    private let wall = (r: 0.6, g: 0.58, b: 0.55)

    func testAGreenBorderIsFound() {
        var detector = GreenScreenDetector()
        XCTAssertTrue(detector.observe(Array(repeating: green, count: 90) + Array(repeating: wall, count: 10)))
    }

    func testAPlainWallIsNot() {
        var detector = GreenScreenDetector()
        XCTAssertFalse(detector.observe(Array(repeating: wall, count: 100)))
    }

    /// Half green - a shirt passing the edge - neither switches on nor off.
    func testTheHysteresisHolds() {
        var detector = GreenScreenDetector()
        let half = Array(repeating: green, count: 50) + Array(repeating: wall, count: 50)
        XCTAssertFalse(detector.observe(half))
        detector.observe(Array(repeating: green, count: 100))
        XCTAssertTrue(detector.observe(half))
        XCTAssertFalse(detector.observe(Array(repeating: wall, count: 100)))
    }
}

final class PersonLayoutTests: XCTestCase {
    func testHeightAndAspect() {
        let frame = PersonLayout(center: CGPoint(x: 0.5, y: 0.5), height: 0.5)
            .frame(canvasWidth: 1920, canvasHeight: 1080, cameraAspect: 16.0 / 9.0)
        XCTAssertEqual(frame.height, 540)
        XCTAssertEqual(frame.width, 960)
        XCTAssertEqual(frame.midX, 960, accuracy: 1)
    }

    func testTheDefaultIsCutOffAtTheBottom() {
        let frame = PersonLayout().frame(canvasWidth: 1920, canvasHeight: 1080, cameraAspect: 16.0 / 9.0)
        XCTAssertGreaterThan(frame.maxY, 1080, "reaches past the bottom, like a presenter")
        XCTAssertLessThan(frame.minY, 1080)
    }

    func testAtLeastAQuarterStaysOnTheCanvas() {
        let frame = PersonLayout(center: CGPoint(x: 5, y: -5), height: 0.5)
            .frame(canvasWidth: 1920, canvasHeight: 1080, cameraAspect: 16.0 / 9.0)
        XCTAssertEqual(frame.minX, 1920 - frame.width * PersonLayout.minimumVisible, accuracy: 1)
        XCTAssertEqual(frame.maxY, frame.height * PersonLayout.minimumVisible, accuracy: 1)
    }

    func testClampedStoresWhereItReallyIs() {
        let layout = PersonLayout(center: CGPoint(x: 5, y: 0.5), height: 3)
            .clamped(canvasWidth: 1920, canvasHeight: 1080, cameraAspect: 16.0 / 9.0)
        XCTAssertEqual(layout.height, 1)
        XCTAssertLessThan(layout.center.x, 1.5)
    }
}

/// End to end on the GPU: a green camera picture with a red "person" in the
/// middle, keyed and placed over a blue screen. Where the green was, the
/// screen shows; the person stays.
final class GreenScreenCompositingTests: XCTestCase {
    private func buffer(width: Int, height: Int, fill: (Int, Int) -> (UInt8, UInt8, UInt8)) throws -> CVPixelBuffer {
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
                let (r, g, b) = fill(x, y)
                row[x * 4] = b; row[x * 4 + 1] = g; row[x * 4 + 2] = r; row[x * 4 + 3] = 255
            }
        }
        return pixelBuffer
    }

    private func pixel(_ buffer: CVPixelBuffer, x: Int, y: Int) throws -> (r: Int, g: Int, b: Int) {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
        let p = base.advanced(by: y * CVPixelBufferGetBytesPerRow(buffer) + x * 4).assumingMemoryBound(to: UInt8.self)
        return (Int(p[2]), Int(p[1]), Int(p[0]))
    }

    func testTheGreenGoesAndThePersonStays() throws {
        let camera = try buffer(width: 160, height: 90) { x, y in
            (60...100).contains(x) && (25...65).contains(y) ? (220, 40, 40) : (30, 200, 50)
        }
        let screen = try buffer(width: 160, height: 90) { _, _ in (20, 40, 220) }
        let key = PersonKeyer().key(camera, choice: .greenScreen)
        XCTAssertEqual(key.method, .greenScreen)

        let output = try XCTUnwrap(FrameCompositor().renderScreenWithPerson(
            screen: screen, camera: key.camera, mask: key.mask, canvasWidth: 160, canvasHeight: 90,
            frame: CGRect(x: 0, y: 0, width: 160, height: 90), mirrorsCamera: false))

        let background = try pixel(output, x: 10, y: 10)
        XCTAssertGreaterThan(background.b, 150, "the screen shows where the green was")
        XCTAssertLessThan(background.g, 110)
        let person = try pixel(output, x: 80, y: 45)
        XCTAssertGreaterThan(person.r, 150, "the person stays")
        XCTAssertLessThan(person.b, 100)
    }
}
