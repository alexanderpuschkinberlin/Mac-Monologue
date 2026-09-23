import XCTest
@testable import Mac_Monologue

final class FaceFramingTests: XCTestCase {
    private func face(x: CGFloat, y: CGFloat) -> CGRect {
        CGRect(x: x - 0.1, y: y - 0.1, width: 0.2, height: 0.2)
    }

    private func settle(_ framing: inout FaceFraming, frames: Int = 120) -> CGRect {
        var crop = framing.crop
        for _ in 0..<frames { crop = framing.step() }
        return crop
    }

    func testStartsCentredAndZoomedIn() {
        let crop = FaceFraming().crop
        XCTAssertEqual(crop.midX, 0.5, accuracy: 0.0001)
        XCTAssertEqual(crop.midY, 0.5, accuracy: 0.0001)
        XCTAssertEqual(crop.width, 1 / FaceFraming.zoom, accuracy: 0.0001)
    }

    func testFollowsAFaceThatMoves() {
        var framing = FaceFraming()
        framing.observe(face: face(x: 0.65, y: 0.5))
        let crop = settle(&framing)
        XCTAssertEqual(crop.midX, 0.65, accuracy: 0.01)
    }

    func testIgnoresSmallMovements() {
        var framing = FaceFraming()
        framing.observe(face: face(x: 0.52, y: 0.5 - FaceFraming.windowSize.height * FaceFraming.headroom))
        let crop = settle(&framing)
        XCTAssertEqual(crop.midX, 0.5, accuracy: 0.0001, "a nod is not a move")
    }

    func testGlidesRatherThanJumps() {
        var framing = FaceFraming()
        framing.observe(face: face(x: 0.7, y: 0.5))
        let first = framing.step()
        XCTAssertLessThan(first.midX, 0.55, "one frame covers only part of the way")
        XCTAssertGreaterThan(first.midX, 0.5)
    }

    func testNeverLeavesThePicture() {
        var framing = FaceFraming()
        framing.observe(face: face(x: 0.98, y: 0.02))
        let crop = settle(&framing, frames: 300)
        XCTAssertLessThanOrEqual(crop.maxX, 1.0001)
        XCTAssertGreaterThanOrEqual(crop.minY, -0.0001)
    }

    func testStaysPutWhenTheFaceIsGone() {
        var framing = FaceFraming()
        framing.observe(face: face(x: 0.65, y: 0.5))
        let settled = settle(&framing)
        framing.observe(face: nil)
        XCTAssertEqual(settle(&framing).midX, settled.midX, accuracy: 0.0001)
    }

    func testLeavesHeadroomAboveTheFace() {
        var framing = FaceFraming()
        framing.observe(face: face(x: 0.5, y: 0.3))
        let crop = settle(&framing)
        XCTAssertGreaterThan(crop.midY, 0.3, "the face sits above the middle of the window")
    }
}
