import XCTest
@testable import Mac_Monologue

final class BubbleLayoutTests: XCTestCase {
    func testEveryCornerAndSizeIsASquareWhollyInsideTheCanvas() {
        let canvas = CGRect(x: 0, y: 0, width: 2560, height: 1654)
        for corner in BubbleCorner.allCases {
            for size in BubbleSize.allCases {
                let frame = BubbleLayout(corner: corner, size: size).frame(canvasWidth: 2560, canvasHeight: 1654)
                XCTAssertEqual(frame.width, frame.height, "\(corner) \(size) must be square")
                XCTAssertTrue(canvas.contains(frame), "\(corner) \(size) must lie inside the canvas")
            }
        }
    }

    func testBottomTrailingSitsAtTheMargin() {
        let frame = BubbleLayout(corner: .bottomTrailing, size: .medium).frame(canvasWidth: 2560, canvasHeight: 1654)
        let margin = (1654 * BubbleLayout.marginFraction).rounded()
        XCTAssertEqual(frame.maxX, 2560 - margin)
        XCTAssertEqual(frame.maxY, 1654 - margin)
        XCTAssertEqual(frame.width, (1654 * 0.22).rounded())
    }

    func testTopLeadingSitsAtTheMargin() {
        let frame = BubbleLayout(corner: .topLeading, size: .small).frame(canvasWidth: 1920, canvasHeight: 1080)
        let margin = (1080 * BubbleLayout.marginFraction).rounded()
        XCTAssertEqual(frame.minX, margin)
        XCTAssertEqual(frame.minY, margin)
    }

    func testSizesGrowInOrder() {
        let widths = BubbleSize.allCases.map {
            BubbleLayout(size: $0).frame(canvasWidth: 2560, canvasHeight: 1440).width
        }
        XCTAssertEqual(widths, widths.sorted())
        XCTAssertEqual(Set(widths).count, 3)
    }

    func testATinyCanvasStillFits() {
        let frame = BubbleLayout(size: .large).frame(canvasWidth: 40, canvasHeight: 30)
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 40, height: 30).contains(frame))
    }

    func testNormalizedFrameMatchesThePixelFrame() {
        let layout = BubbleLayout(corner: .topTrailing, size: .large)
        let pixels = layout.frame(canvasWidth: 2560, canvasHeight: 1654)
        let normalized = layout.normalizedFrame(canvasWidth: 2560, canvasHeight: 1654)
        XCTAssertEqual(normalized.minX * 2560, pixels.minX, accuracy: 0.001)
        XCTAssertEqual(normalized.minY * 1654, pixels.minY, accuracy: 0.001)
        XCTAssertEqual(normalized.width * 2560, pixels.width, accuracy: 0.001)
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 1, height: 1).contains(normalized))
    }
}
