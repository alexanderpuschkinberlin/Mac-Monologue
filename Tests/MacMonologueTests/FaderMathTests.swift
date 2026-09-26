import XCTest
@testable import Mac_Monologue

final class FaderMathTests: XCTestCase {
    func testTheEndsAndTheCentre() {
        XCTAssertEqual(FaderMath.value(forX: 6, width: 150, capWidth: 12), -1)
        XCTAssertEqual(FaderMath.value(forX: 144, width: 150, capWidth: 12), 1)
        XCTAssertEqual(FaderMath.value(forX: 75, width: 150, capWidth: 12), 0)
        XCTAssertEqual(FaderMath.value(forX: -40, width: 150, capWidth: 12), -1, "clamped outside the rail")
    }

    func testTheCentreCatches() {
        XCTAssertEqual(FaderMath.snapped(0.05), 0)
        XCTAssertEqual(FaderMath.snapped(-0.05), 0)
        XCTAssertEqual(FaderMath.snapped(0.1), 0.1)
    }

    func testArrowKeysComeBackToExactlyTheCentre() {
        var value: Float = -0.3
        for _ in 0..<3 { value = FaderMath.step(value, by: 0.1) }
        XCTAssertEqual(value, 0)
        XCTAssertEqual(FaderMath.step(1, by: 0.1), 1, "stays at the end")
    }

    func testSpokenValue() {
        XCTAssertEqual(FaderMath.spokenValue(0), "both full")
        XCTAssertEqual(FaderMath.spokenValue(-0.5), "Mac sound 25 %")
        XCTAssertEqual(FaderMath.spokenValue(1), "voice 0 %")
    }
}
