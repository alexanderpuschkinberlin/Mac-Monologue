import XCTest
@testable import Mac_Monologue

final class ScreenCanvasTests: XCTestCase {
    func testMacBookProDisplay() {
        let size = ScreenCanvas.size(forDisplayWidth: 3456, height: 2234)
        XCTAssertEqual(size.width, 2560)
        XCTAssertEqual(size.height, 1654)
    }

    func testFiveKDisplay() {
        let size = ScreenCanvas.size(forDisplayWidth: 5120, height: 2880)
        XCTAssertEqual(size.width, 2560)
        XCTAssertEqual(size.height, 1440)
    }

    func testNeverScalesUp() {
        let size = ScreenCanvas.size(forDisplayWidth: 1280, height: 800)
        XCTAssertEqual(size.width, 1280)
        XCTAssertEqual(size.height, 800)
    }

    func testPortraitDisplayUsesItsLongEdge() {
        let size = ScreenCanvas.size(forDisplayWidth: 2160, height: 3840)
        XCTAssertEqual(size.height, 2560)
        XCTAssertEqual(size.width, 1440)
    }

    func testBothEdgesAreEven() {
        for (width, height) in [(1281, 801), (3457, 2235), (2561, 1601), (3, 3)] {
            let size = ScreenCanvas.size(forDisplayWidth: width, height: height)
            XCTAssertEqual(size.width % 2, 0, "\(width)x\(height)")
            XCTAssertEqual(size.height % 2, 0, "\(width)x\(height)")
        }
    }

    func testAspectRatioIsPreserved() {
        for (width, height) in [(3456, 2234), (5120, 2880), (3024, 1964), (6016, 3384)] {
            let size = ScreenCanvas.size(forDisplayWidth: width, height: height)
            let original = Double(width) / Double(height)
            let scaled = Double(size.width) / Double(size.height)
            XCTAssertEqual(scaled, original, accuracy: original * 0.005, "\(width)x\(height)")
        }
    }
}
